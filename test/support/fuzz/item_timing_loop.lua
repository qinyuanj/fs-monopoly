-- 道具时机 fuzz（loop 层生产帧路径）。来源：残留 pending_choice 诊断（5ce62507，
-- 当初就是本探针抓到 seed 6/23/35 的门控活锁）。
-- 走 gameplay_loop.tick + turn_dispatch.dispatch_action（真实门控/超时/倒计时 +
-- 可控时钟），随机让"玩家发呆"使倒计时到期路径被覆盖。断言：
--   1) 道具时机有可用牌且非 done 重入必开窗（规则层 spy 与 item_timing_fuzz 同款）。
--   2) 窗口 pending 且无阻断时，玩家的操作不能被门控连续拒绝 25 次
--      （拒绝活锁 = "点不了干等倒计时"的用户形态）。
--   3) 有限步数内回合必然推进（choice 超时兜底本身就应保证这点）。
-- 驱动器策略与 test_item_timing_fuzz.lua 相同（被弹回的选项不再点、死胡同取消并
-- 标记来源道具），改动前先读那边的头注释。
-- 用法：随默认 verify 的 behavior 车道跑（默认 400 seeds 总量，~3s）；本文件是驱动器，
-- seed 分片薄 spec 见 test/behavior/turn/test_item_timing_loop_fuzz*.lua（#190 分片
-- 让 LPT 并行吸收，总 seed 数不变）。MONOPOLY_FUZZ_SEEDS=2000 放大做 soak；
-- 注意：抓取力依赖 seed 覆盖面（当初的活锁在换 Rng 后最早红点是 seed 37），
-- 别把默认 seed 数往下调。
-- FUZZ_ONLY_SEED=<n> 单 seed 复放（自动附带 resolve/deadline 细 trace）。
require("test.bootstrap").install_package_paths()
local luassert = require("packages.test_runner.cache_loader").verified_module("luassert")
  or assert(require("test.support.luassert_loader").load())
local support = require("test.support.shared_support")
local fixtures = require("test.support.gameplay_fixtures")
local property = require("test.support.property")
local gameplay_loop = require("src.turn.loop.init")
local turn_dispatch = require("src.turn.actions.action_dispatcher")
local loop_ports = require("src.turn.loop.ports")
local availability = require("src.rules.items.availability")
local item_phase = require("src.rules.items.phase")
local item_ids = require("src.config.gameplay.item_ids")
local auto_play_port = require("src.rules.ports.auto_play")
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

local MAX_STEPS = 3000
local TURNS_PER_SEED = 6

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

-- resolve/deadline spy：单 seed 复放时打出结算细节（stay/拒因/超时归属）。
local function _install_focus_spies(trace)
  local choice_resolver = require("src.rules.choice.resolver")
  local deadlines = require("src.turn.deadlines")
  local real_resolve = choice_resolver.resolve
  choice_resolver.resolve = function(game, choice, action, opts)
    local res = real_resolve(game, choice, action, opts)
    trace[#trace + 1] = string.format(
      "    resolve kind=%s id=%s action=%s option=%s -> stay=%s status=%s reason=%s pending_after=%s",
      tostring(choice and choice.kind), tostring(choice and choice.id),
      tostring(action and action.type), tostring(action and action.option_id),
      tostring(type(res) == "table" and res.stay), tostring(type(res) == "table" and res.status),
      tostring(type(res) == "table" and res.reason),
      tostring(game.turn.pending_choice and game.turn.pending_choice.id))
    return res
  end
  local real_deadline_resolve = deadlines.resolve_choice
  deadlines.resolve_choice = function(game, state, choice, mode, action)
    trace[#trace + 1] = string.format("    deadline_resolve kind=%s id=%s mode=%s action=%s",
      tostring(choice and choice.kind), tostring(choice and choice.id), tostring(mode),
      tostring(action and action.type))
    return real_deadline_resolve(game, state, choice, mode, action)
  end
  return function()
    choice_resolver.resolve = real_resolve
    deadlines.resolve_choice = real_deadline_resolve
  end
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

-- 玩家意图（不直接动 game 内部，全部走 turn_dispatch 生产入口）。
-- attempts：同一 choice id 的 select 次数与被弹回的选项/来源道具标记。
local function _build_player_action(g, rng, attempts)
  local turn = g.turn
  local pending = turn.pending_choice
  local actor = g:current_player().id
  if pending ~= nil then
    local opts = pending.options or {}
    -- 商店购买与道具时机无关，直接取消离开，避免无限购买循环。
    if pending.kind == "market_buy" and pending.allow_cancel ~= false then
      return { type = "choice_cancel", choice_id = pending.id, actor_role_id = actor }, "cancel:market_buy"
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
      return {
        type = "choice_select",
        choice_id = pending.id,
        option_id = pick.id,
        actor_role_id = actor,
        _pick_key = tostring(pending.kind) .. ":" .. tostring(pick.id),
        _choice_id = pending.id,
      }, "select:" .. tostring(pending.kind) .. ":" .. tostring(pick.id)
    end
    if pending.allow_cancel ~= false then
      -- 跟随选择走了死胡同被取消：把来源道具一并标记，避免窗口重开后死磕同一张卡
      local origin_item = pending.meta and pending.meta.item_id or nil
      if origin_item ~= nil then
        attempts["item_phase_passive:" .. tostring(origin_item)] = true
      end
      return { type = "choice_cancel", choice_id = pending.id, actor_role_id = actor },
        "cancel:" .. tostring(pending.kind)
    end
    return nil, nil
  end
  if turn.phase == "wait_action" then
    return { type = "ui_button", id = "next", actor_role_id = actor }, "next"
  end
  return nil, nil
end

local function _run_one_seed(seed)
  local rng = property.Rng.new(seed * 2654435761)
  -- 游戏内部掷骰/抽卡走全局 math.random：每 seed 重播，保证单 seed 可复现。
  math.randomseed(seed)
  local g = support.new_game({ ai = {} })
  local state = fixtures.build_loop_state()
  local now = 0
  -- 回合默认步进与测试 UI 接线、可控时钟组合；modal/anim 保持 noop。
  state.gameplay_loop_ports = loop_ports.resolve({
    ui_sync = {
      on_pending_choice = state.gameplay_loop_ports.ui_sync.on_pending_choice,
      resolve_choice_ui_state = state.gameplay_loop_ports.ui_sync.resolve_choice_ui_state,
    },
    clock = {
      wall_now_seconds = function() return now end,
      wall_diff_seconds = function(a, b) return (a or 0) - (b or 0) end,
      cpu_now_seconds = function() return now end,
      cpu_diff_seconds = function(a, b) return (a or 0) - (b or 0) end,
    },
  })
  gameplay_loop.set_game(state, g)
  local records = {}
  local restore_run = _install_run_spy(records)
  local trace = {}
  local restore_focus = nil
  if ONLY_SEED ~= nil then
    restore_focus = _install_focus_spies(trace)
  end
  local ok, err = pcall(function()
    _randomize_board(g, rng)
    local given = _fill_random_inventory(g:current_player(), rng)
    trace[#trace + 1] = "inventory:" .. table.concat(given, ",")
    -- 对齐 gameplay_start：把回合机踩进第一个 wait
    g:advance_turn()

    local turns_played = 0
    local last_index = g.turn.current_player_index
    local steps = 0
    local attempts = {}
    local idle_ticks = 0
    local reject_streak = 0
    while steps < MAX_STEPS do
      steps = steps + 1
      local dt = 0.1 + (rng:int(1, 10) - 1) * 0.1
      now = now + dt
      gameplay_loop.tick(g, state, dt)

      if idle_ticks > 0 then
        idle_ticks = idle_ticks - 1
        trace[#trace + 1] = "idle phase=" .. tostring(g.turn.phase)
      else
        if rng:int(1, 12) == 1 then
          -- 玩家发呆：让倒计时/超时路径真实发生
          idle_ticks = rng:int(1, 30)
        else
          local action, label = _build_player_action(g, rng, attempts)
          if action ~= nil then
            local pick_key = action._pick_key
            local choice_id = action._choice_id
            action._pick_key = nil
            action._choice_id = nil
            local res = turn_dispatch.dispatch_action(g, state, action)
            local status = type(res) == "table" and res.status or tostring(res)
            trace[#trace + 1] = tostring(label) .. " -> " .. tostring(status)
              .. " phase=" .. tostring(g.turn.phase) .. " p" .. tostring(g.turn.current_player_index)
            if status == "rejected" and g.turn.pending_choice ~= nil then
              reject_streak = reject_streak + 1
              if reject_streak >= 25 then
                error("gate livelock: choice pending but actions rejected 25x (点不了干等倒计时形态)")
              end
            else
              reject_streak = 0
            end
            if pick_key ~= nil and choice_id ~= nil then
              local now_pending = g.turn.pending_choice
              if now_pending ~= nil and now_pending.id == choice_id then
                -- select 被弹回（执行拒绝留窗）：标记该选项，避免驱动器死磕
                attempts[pick_key] = true
              end
            end
          else
            trace[#trace + 1] = "noop phase=" .. tostring(g.turn.phase)
          end
        end
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
  if restore_focus ~= nil then
    restore_focus()
  end
  restore_run()
  return ok, err, records, trace
end

local function _record_line(r)
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
  local tail = ONLY_SEED ~= nil and 300 or 60
  lines[#lines + 1] = "trace(last " .. tail .. "):"
  local from = math.max(1, #trace - tail)
  for i = from, #trace do
    lines[#lines + 1] = "  " .. trace[i]
  end
  return table.concat(lines, "\n")
end

local function _find_violation(records)
  for _, r in ipairs(records) do
    if not r.auto and not r.done_at_entry and r.offerable > 0 and not r.waiting then
      return "skipped ask: phase=" .. r.phase .. " offerable=" .. r.offerable
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
  luassert.is.equal(0, #failures, "\n" .. table.concat(failures, "\n----\n"))
end

return M
