-- 道具时机 fuzz（规则 + 调度层）。来源：残留 pending_choice 诊断（5ce62507）。
-- 真实回合机 + 随机地产世界 + 多回合双真人 + 随机道具/动画交错，按 seed 重放，断言：
--   1) 每个启用的道具时机（pre_action/pre_move/post_action），人类玩家有可用牌
--      且非 done 重入时，item_phase.run 必须开出窗口（waiting）。
--   2) 落地结算 pipeline 扫描出可选效果（免费卡/强征卡/买地/加盖…）时必须开询问。
--   3) 回合驱动在有限步数内必然推进（不卡死 = 不"干等倒计时"）。
-- 驱动器模拟真人：被弹回的选项不再点、跟随选择走进死胡同就取消并放弃来源道具
-- （设计允许的"执行失败留窗"如偷窃 bag_full 不算卡死）。
-- 用法：随默认 verify 的 behavior 车道跑（默认 400 seeds 总量，~1s）；本文件是驱动器，
-- seed 分片薄 spec 见 test/behavior/rules/items/test_item_timing_fuzz*.lua（#190 分片
-- 让 LPT 并行吸收，总 seed 数不变）。MONOPOLY_FUZZ_SEEDS=2000 放大做 soak；
-- FUZZ_ONLY_SEED=<n> 单 seed 复放（失败输出自带完整 trace）。
require("test.bootstrap").install_package_paths()
local luassert = require("packages.test_runner.cache_loader").verified_module("luassert")
  or assert(require("test.support.luassert_loader").load())
local support = require("test.support.shared_support")
local property = require("test.support.property")
local availability = require("src.rules.items.availability")
local item_phase = require("src.rules.items.phase")
local item_ids = require("src.config.gameplay.item_ids")
local auto_play_port = require("src.rules.ports.auto_play")
local effect_pipeline = require("src.rules.effects.pipeline")
local effect_runner = require("src.rules.effects.runner")
local tip_queue = require("src.foundation.tips")
local config_reset = require("test.support.config_reset")

local POOL = {
  item_ids.free_rent,
  item_ids.remote_dice,
  item_ids.dice_multiplier,
  item_ids.roadblock,
  item_ids.mine,
  item_ids.clear_obstacles,
  item_ids.steal,
  item_ids.monster,
  item_ids.strong,
  item_ids.tax_free,
  item_ids.share_wealth,
  item_ids.exile,
  item_ids.missile,
  item_ids.tax,
  item_ids.invite_deity,
  item_ids.send_poor,
  item_ids.rich,
  item_ids.poor,
  item_ids.angel,
}

local MAX_STEPS = 1200
local TURNS_PER_SEED = 8

local function _env_int(name)
  local raw = os.getenv(name)
  if raw == nil or raw == "" then
    return nil
  end
  local ok, value = pcall(function()
    return math.tointeger(0 + raw)
  end)
  if ok then
    return value
  end
  return nil
end

local SEED_COUNT = _env_int("MONOPOLY_FUZZ_SEEDS") or 400
local ONLY_SEED = _env_int("FUZZ_ONLY_SEED")

local function _count_offerable(g, player, phase)
  local n = 0
  for _, it in ipairs(player.inventory.items or {}) do
    if it ~= false and it.id ~= nil and availability.can_offer_in_phase(g, player, it.id, phase) then
      n = n + 1
    end
  end
  return n
end

local function _install_run_spy(records)
  local real_run = item_phase.run
  item_phase.run = function(turn_mgr, phase, args)
    local g = turn_mgr.game
    local player = args and args.player
    local rec = nil
    if player ~= nil and item_phase.is_enabled(phase) then
      local phase_states = g.turn.item_phase
      local phase_state = phase_states and phase_states[phase]
      rec = {
        kind = "item_phase",
        phase = phase,
        done_at_entry = (phase_state and phase_state.done == true) or false,
        offerable = _count_offerable(g, player, phase),
        auto = auto_play_port.is_computer_controlled(g, player) == true,
      }
    end
    local res = real_run(turn_mgr, phase, args)
    if rec ~= nil then
      rec.waiting = type(res) == "table" and res.waiting == true
      rec.pending_kind = g.turn.pending_choice and g.turn.pending_choice.kind or nil
      records[#records + 1] = rec
    end
    return res
  end
  return function()
    item_phase.run = real_run
  end
end

local function _count_scanned_optional(effect_defs, player, tile, game_ctx)
  local ok, scanned = pcall(effect_runner.scan, effect_defs, player, tile, game_ctx)
  if not ok or type(scanned) ~= "table" then
    return nil
  end
  local mandatory, optional = 0, 0
  for _, entry in ipairs(scanned) do
    if entry.ok then
      if entry.mandatory then
        mandatory = mandatory + 1
      else
        optional = optional + 1
      end
    end
  end
  return optional, mandatory
end

-- 落地/结算可选效果询问 spy：pipeline 扫出可选效果却没有 waiting 询问 = 静默吞掉。
local function _install_pipeline_spy(records)
  local real_run = effect_pipeline.run
  effect_pipeline.run = function(effect_defs, player, tile, game_ctx, opts)
    local optional_count, mandatory_count = _count_scanned_optional(effect_defs, player, tile, game_ctx)
    local res = real_run(effect_defs, player, tile, game_ctx, opts)
    if optional_count ~= nil then
      records[#records + 1] = {
        kind = "pipeline",
        optional = optional_count,
        mandatory = mandatory_count,
        allow_optional = not (opts and opts.allow_optional == false),
        auto = auto_play_port.is_computer_controlled(game_ctx and game_ctx.game, player) == true,
        waiting = type(res) == "table" and res.waiting == true,
        res_is_nil = res == nil,
        pending_kind = game_ctx and game_ctx.game and game_ctx.game.turn.pending_choice
          and game_ctx.game.turn.pending_choice.kind or nil,
      }
    end
    return res
  end
  return function()
    effect_pipeline.run = real_run
  end
end

-- resolve 结果 spy：stay/拒因直接进 trace，钉"选了没反应"的循环。仅单 seed 复放时装。
local function _install_resolver_spy(trace)
  local choice_resolver = require("src.rules.choice.resolver")
  local real_resolve = choice_resolver.resolve
  choice_resolver.resolve = function(game, choice, action, opts)
    local res = real_resolve(game, choice, action, opts)
    trace[#trace + 1] = string.format("    resolve kind=%s action=%s option=%s -> stay=%s status=%s reason=%s",
      tostring(choice and choice.kind), tostring(action and action.type), tostring(action and action.option_id),
      tostring(type(res) == "table" and res.stay), tostring(type(res) == "table" and res.status),
      tostring(type(res) == "table" and res.reason))
    return res
  end
  return function()
    choice_resolver.resolve = real_resolve
  end
end

-- 单步驱动：模拟宿主/玩家对当前局面做一件事。返回描述串（trace 用），nil = 无事可做。
-- attempts：同一 choice id 的 select 次数与被弹回的选项。
local function _drive_one_step(g, rng, attempts)
  local turn = g.turn
  -- 动画优先收尾，且按当前 wait 状态定向派发（不匹配的 done 会被 wait 吞掉）：
  -- 真实宿主也是动画播完才轮到玩家点窗口。
  if turn.phase == "wait_action_anim" and turn.action_anim ~= nil then
    g:dispatch_action({ type = "action_anim_done", seq = turn.action_anim.seq })
    return "action_anim_done"
  end
  if turn.phase == "wait_move_anim" and turn.move_anim ~= nil then
    g:dispatch_action({ type = "move_anim_done", seq = turn.move_anim.seq })
    return "move_anim_done"
  end
  -- 回合间隔/扣留等待由 loop 层 timer 用真实 dt 驱动：这里模拟计时到期。
  if turn.phase == "inter_turn_wait" then
    turn.inter_turn_wait_active = false
    tip_queue.clear()
    g:advance_turn()
    return "inter_turn_elapsed"
  end
  if turn.phase == "detained_wait" then
    turn.detained_wait_active = false
    g:advance_turn()
    return "detained_elapsed"
  end
  local pending = turn.pending_choice
  if pending ~= nil then
    local opts = pending.options or {}
    -- 商店购买与道具时机无关，直接取消离开，避免无限购买循环。
    if pending.kind == "market_buy" and pending.allow_cancel ~= false then
      g:dispatch_action({
        type = "choice_cancel",
        choice_id = pending.id,
        actor_role_id = g:current_player().id,
      })
      return "cancel:market_buy"
    end
    local tried = attempts[pending.id] or 0
    -- 被弹回过的选项不再选（真人不会反复点同一个失败目标/卡）
    local fresh = {}
    for _, opt in ipairs(opts) do
      if not attempts[tostring(pending.kind) .. ":" .. tostring(opt.id)] then
        fresh[#fresh + 1] = opt
      end
    end
    local exhausted = #fresh == 0
    local pool = exhausted and opts or fresh
    if #opts > 0 and ((tried < 3 and not exhausted) or pending.allow_cancel == false) then
      attempts[pending.id] = tried + 1
      local pick = rng:pick(pool)
      g:dispatch_action({
        type = "choice_select",
        choice_id = pending.id,
        option_id = pick.id,
        actor_role_id = g:current_player().id,
      })
      local now_pending = g.turn.pending_choice
      if now_pending ~= nil and now_pending.id == pending.id then
        -- select 被弹回（执行拒绝留窗）：标记该选项，避免驱动器死磕
        attempts[tostring(pending.kind) .. ":" .. tostring(pick.id)] = true
      end
      return "select:" .. tostring(pending.kind) .. ":" .. tostring(pick.id)
    end
    if pending.allow_cancel ~= false then
      -- 跟随选择走了死胡同被取消：把来源道具一并标记，避免窗口重开后死磕同一张卡
      local origin_item = pending.meta and pending.meta.item_id or nil
      if origin_item ~= nil then
        attempts["item_phase_passive:" .. tostring(origin_item)] = true
      end
      g:dispatch_action({
        type = "choice_cancel",
        choice_id = pending.id,
        actor_role_id = g:current_player().id,
      })
      return "cancel:" .. tostring(pending.kind)
    end
    return nil
  end
  if turn.phase == "wait_action" then
    g:dispatch_action({ type = "ui_button", id = "next", actor_role_id = g:current_player().id })
    return "next"
  end
  g:advance_turn()
  return "step"
end

local function _fill_random_inventory(player, rng)
  player.inventory:clear()
  local n = rng:int(1, 5)
  local given = {}
  for _ = 1, n do
    local id = rng:pick(POOL)
    player.inventory:add({ id = id })
    given[#given + 1] = id
  end
  return given
end

-- 随机地产世界：让"落地在对手/自己地块、可买地、可加盖"都有概率出现。
local function _randomize_board(g, rng)
  for _, tile_ref in ipairs(g.board.path) do
    if tile_ref.type == "land" then
      local roll = rng:int(1, 4)
      if roll == 2 or roll == 3 then
        local owner = g.players[roll - 1]
        g:set_tile_owner(tile_ref, owner.id)
        g:set_player_property(owner, tile_ref.id, true)
        local level = rng:int(0, 3)
        if level > 0 then
          g:set_tile_level(tile_ref, level)
        end
      end
    end
  end
end

local function _run_one_seed(seed)
  local rng = property.Rng.new(seed * 2654435761)
  -- 游戏内部掷骰/抽卡走全局 math.random：每 seed 重播，保证单 seed 可复现。
  math.randomseed(seed)
  local g = support.new_game({ ai = {} })
  if rng:bool() then
    g.anim_gate_port = { wait_move_anim = true, wait_action_anim = true }
  end
  local records = {}
  local restore_run = _install_run_spy(records)
  local restore_pipeline = _install_pipeline_spy(records)
  local trace = {}
  local restore_resolver = nil
  if ONLY_SEED ~= nil then
    restore_resolver = _install_resolver_spy(trace)
  end
  local ok, err = pcall(function()
    _randomize_board(g, rng)
    local given = _fill_random_inventory(g:current_player(), rng)
    trace[#trace + 1] = "inventory:" .. table.concat(given, ",")
    trace[#trace + 1] = "anim_gate:" .. tostring(g.anim_gate_port ~= nil)

    local turns_played = 0
    local last_index = g.turn.current_player_index
    local steps = 0
    local attempts = {}
    while steps < MAX_STEPS do
      steps = steps + 1
      local did = _drive_one_step(g, rng, attempts)
      trace[#trace + 1] = tostring(did) .. " phase=" .. tostring(g.turn.phase)
        .. " p" .. tostring(g.turn.current_player_index)
      if did == nil then
        error("stuck: nothing drivable (等倒计时形态) phase=" .. tostring(g.turn.phase))
      end
      if g.finished then
        break
      end
      if g.turn.current_player_index ~= last_index then
        turns_played = turns_played + 1
        last_index = g.turn.current_player_index
        if turns_played >= TURNS_PER_SEED then
          break
        end
        -- 窗口已开时不许外部改背包（生产中不存在的竞态）
        if g.turn.pending_choice == nil then
          local refill = _fill_random_inventory(g:current_player(), rng)
          trace[#trace + 1] = "refill p" .. tostring(last_index) .. ":" .. table.concat(refill, ",")
        else
          trace[#trace + 1] = "refill skipped (window open) p" .. tostring(last_index)
        end
        for k in pairs(attempts) do
          attempts[k] = nil
        end
      end
    end
    if steps >= MAX_STEPS then
      error("stuck: did not finish " .. TURNS_PER_SEED .. " turns within " .. MAX_STEPS .. " steps")
    end
  end)
  if restore_resolver ~= nil then
    restore_resolver()
  end
  restore_pipeline()
  restore_run()
  return ok, err, records, trace
end

local function _record_line(r)
  if r.kind == "pipeline" then
    return string.format("  pipeline optional=%s mandatory=%s allow=%s auto=%s waiting=%s res_nil=%s pending=%s",
      tostring(r.optional), tostring(r.mandatory), tostring(r.allow_optional), tostring(r.auto),
      tostring(r.waiting), tostring(r.res_is_nil), tostring(r.pending_kind))
  end
  return string.format("  item_phase phase=%s done_at_entry=%s offerable=%d auto=%s waiting=%s pending=%s",
    r.phase, tostring(r.done_at_entry), r.offerable, tostring(r.auto), tostring(r.waiting), tostring(r.pending_kind))
end

local function _format_failure(seed, err, records, trace)
  local lines = { "seed=" .. seed .. " err=" .. tostring(err)
    .. " (复放: FUZZ_ONLY_SEED=" .. seed .. " lua5.4 tools/cli.lua spec-lane --profile behavior)" }
  lines[#lines + 1] = "records(last 25):"
  local rec_from = math.max(1, #records - 25)
  for i = rec_from, #records do
    lines[#lines + 1] = _record_line(records[i])
  end
  local tail = ONLY_SEED ~= nil and 260 or 50
  lines[#lines + 1] = "trace(last " .. tail .. "):"
  local from = math.max(1, #trace - tail)
  for i = from, #trace do
    lines[#lines + 1] = "  " .. trace[i]
  end
  return table.concat(lines, "\n")
end

local function _find_violation(records)
  for _, r in ipairs(records) do
    if r.kind == "item_phase" then
      if not r.auto and not r.done_at_entry and r.offerable > 0 and not r.waiting then
        return "skipped ask: phase=" .. r.phase .. " offerable=" .. r.offerable
      end
    elseif r.kind == "pipeline" then
      if not r.auto and r.allow_optional and (r.optional or 0) > 0 and r.res_is_nil then
        return "pipeline dropped optional effects: optional=" .. tostring(r.optional)
      end
    end
  end
  return nil
end


-- 行级插桩环境（uml crap 经 luacov 挂 debug hook 采集覆盖率）下空跑：探针职责是
-- 时序活锁捕捉，不是覆盖率来源；插桩把 fuzz 热循环拖慢一个量级。迁移前 property
-- 车道本就不进 coverage/crap 口径（#190），这里保持一致。
local function _instrumented()
  return debug.gethook() ~= nil
end

local M = {
  seed_count = SEED_COUNT,
  only_seed = ONLY_SEED,
}

-- 均分 seeds 成 total 片，返回第 index 片的 [from, to]（随 MONOPOLY_FUZZ_SEEDS 缩放）。
function M.shard_range(index, total)
  local per = math.ceil(SEED_COUNT / total)
  local from = (index - 1) * per + 1
  local to = math.min(SEED_COUNT, index * per)
  return from, to
end

function M.reset()
  config_reset.reset_all()
end

-- 跑 [seed_from, seed_to] 分片。FUZZ_ONLY_SEED 复放约定：由覆盖该 seed 的分片跑；
-- seed 超出总量时归首片（seed_from == 1），其余分片空跑。
function M.run_range(seed_from, seed_to)
  if _instrumented() then
    return
  end
  if ONLY_SEED ~= nil then
    local in_range = ONLY_SEED >= seed_from and ONLY_SEED <= seed_to
    local orphan = (ONLY_SEED < 1 or ONLY_SEED > SEED_COUNT) and seed_from == 1
    if not (in_range or orphan) then
      return
    end
    seed_from, seed_to = ONLY_SEED, ONLY_SEED
  end
  local failures = {}
  for seed = seed_from, seed_to do
    local ok, err, records, trace = _run_one_seed(seed)
    local violation = nil
    if ok then
      violation = _find_violation(records)
    end
    if not ok then
      failures[#failures + 1] = _format_failure(seed, err, records, trace)
    elseif violation ~= nil then
      failures[#failures + 1] = _format_failure(seed, violation, records, trace)
    end
    if #failures >= 3 then
      break
    end
  end
  luassert.truthy(#failures == 0, "\n" .. table.concat(failures, "\n----\n"))
end

return M
