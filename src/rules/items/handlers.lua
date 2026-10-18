local logger = require("src.foundation.log")
local auto_play_port = require("src.rules.ports.auto_play")
local effects = require("src.rules.items.post_effects")
local inventory = require("src.rules.items.inventory")
local number_utils = require("src.foundation.number")
local event_kinds = require("src.config.gameplay.event_kinds")
local roadblock = require("src.rules.items.roadblock")
local remote_dice = require("src.rules.items.remote_dice")
local demolish = require("src.rules.items.demolish")
local item_ids = require("src.config.gameplay.item_ids")
local timing = require("src.config.gameplay.timing")
local event_feed = require("src.rules.ports.event_feed")
local action_anim_port = require("src.foundation.ports.action_anim")
local board_query = require("src.rules.board.query")
local settlement = require("src.rules.items.settlement")
local target_resolve = require("src.rules.items.target_resolve")
local use_result = require("src.rules.items.use_result")

local handlers = {}
-- timing 是静态配置,action_anim_default_seconds 键恒在,`or 1.0` 是死防御(#259 删除)。
local action_anim_duration = timing.action_anim_default_seconds

local function _queue_target_player_anim(game, user, item_id, target)
  return action_anim_port.queue(game, {
    kind = "item_target_player",
    player_id = user.id,
    target_player_id = target.id,
    item_id = item_id,
    item_name = inventory.item_name(item_id),
    duration = action_anim_duration,
  })
end

local function _apply_share_wealth_context(context, item_id)
  if item_id ~= item_ids.share_wealth then return end
  context.share_wealth_cash_receive_mode = "item_target_player_only"
  context.suppress_cash_receive_anim = true
end

local function _finalize_apply(apply_res, queued)
  if type(apply_res) == "table" then
    apply_res.ok = true
    if queued then apply_res.action_anim = true end
    return apply_res
  end
  return { ok = true, action_anim = queued }
end

-- 目标玩家道具的纯 applier:效果 + 目标动画。消耗归 settlement
-- (偷窃卡经 context.commit_item_use 在 apply 中途走台账自耗)。
function handlers.apply_target_player(game, user, item_id, target, context, commit)
  context = context or {}
  _apply_share_wealth_context(context, item_id)
  context.commit_item_use = commit
  local apply_res = effects.apply_target(game, user, item_id, target, context)
  if use_result.canonicalize(apply_res).status ~= "applied" then
    return apply_res
  end
  local already_queued = type(apply_res) == "table" and apply_res.action_anim
  local queued = (not already_queued) and _queue_target_player_anim(game, user, item_id, target)
  return _finalize_apply(apply_res, queued)
end

local function _settle_target_player(game, player, item_id, target, context, opts)
  return settlement.execute(game, player, item_id, function(commit)
    return handlers.apply_target_player(game, player, item_id, target, context, commit)
  end, {
    consume = "after_success",
    fallback_reason = opts and opts.fallback_reason or "invalid_target",
  })
end

local function _no_candidate_result(game, player, item_id, context, opts)
  if opts.on_empty then
    opts.on_empty(game, player, item_id, context)
  end
  return false
end

local function _await_choice_result(game, player, item_id, candidates, context, opts)
  -- 无 opts.choice_spec 存在性守卫:唯一调用方 _run_item_choice_flow 的
  -- opts 是字面量构造,choice_spec 恒在(#259 删除);工厂返回值守卫保留。
  local choice_spec = assert(opts.choice_spec(game, player, item_id, candidates, context), "missing choice_spec")
  return {
    waiting = true,
    intent = {
      kind = "need_choice",
      choice_spec = choice_spec,
    },
  }
end

local function _run_item_choice_flow(game, player, item_id, context, opts)
  context = context or {}
  local candidates = assert(opts.candidates(game, player, item_id, context), "missing candidates")
  if #candidates == 0 then
    return _no_candidate_result(game, player, item_id, context, opts)
  end

  -- 无 opts.ai_select 守卫:同上,字面量 opts 恒提供(#259 删除)。
  if context.is_computer_controlled then
    return opts.ai_select(game, player, item_id, candidates, context)
  end

  return _await_choice_result(game, player, item_id, candidates, context, opts)
end

local function _use_on_named_target(game, player, item_id, context, resolve_candidates)
  local target = target_resolve.resolve_valid_target(game, player, item_id, context, resolve_candidates)
  if not target then return false end
  return _settle_target_player(game, player, item_id, target, context, {
    fallback_reason = context.reject_reason_fallback or "invalid_target",
  })
end

local function _seat_by_role_id(inner_game)
  local seat_by_role_id = {}
  for seat, p in ipairs(inner_game.players or {}) do
    seat_by_role_id[p.id] = seat
  end
  return seat_by_role_id
end

-- 单个候选目标的选项行:神标识与现金文案并入 body 行,槽位布局按座位号。
local function _append_target_candidate_option(game, inner_game, t, i, options, body_lines, slot_layout, seat_by_role_id)
  local deity_text = ""
  local deity_type = inner_game:player_deity_type(t)
  if deity_type then
    deity_text = " 神:" .. deity_type
  end
  local cash_text = number_utils.format_integer_part(game:player_cash(t))
  table.insert(body_lines, t.name .. " 现金:" .. cash_text .. deity_text)
  table.insert(options, { id = t.id, label = t.name })
  slot_layout[i] = seat_by_role_id[t.id] or i
end

function handlers.handle_target_player_item(game, player, item_id, context)
  context = context or {}
  local resolve_candidates = context.resolve_target_candidates
  assert(resolve_candidates ~= nil, "missing resolve_target_candidates")
  if context.target_id then
    return _use_on_named_target(game, player, item_id, context, resolve_candidates)
  end

  return _run_item_choice_flow(game, player, item_id, context, {
    candidates = resolve_candidates,
    on_empty = function()
      -- migrated as DEV(#522 对齐同文件路障 on_empty 处置):正常对局边界
      -- (无可选目标),非缺陷,无玩家可见状态变更,info 留痕即可。
      logger.info("没有可选择的目标玩家")
    end,
    ai_select = function(inner_game, inner_player, inner_item_id, candidates)
      local target = auto_play_port.pick_target_player(inner_game, inner_player, inner_item_id, candidates)
      assert(target ~= nil, "missing target player")
      return _settle_target_player(inner_game, inner_player, inner_item_id, target, context, nil)
    end,
    choice_spec = function(inner_game, inner_player, inner_item_id, candidates)
      local options = {}
      local body_lines = {}
      local slot_layout = {}
      local seat_by_role_id = _seat_by_role_id(inner_game)
      for i, t in ipairs(candidates) do
        _append_target_candidate_option(game, inner_game, t, i, options, body_lines, slot_layout, seat_by_role_id)
      end
      return {
        kind = "item_target_player",
        route_key = "player",
        pre_confirm_on_select = false,
        owner_role_id = inner_player.id,
        title = inventory.item_name(inner_item_id) .. "：选择目标玩家",
        body_lines = body_lines,
        options = options,
        target_slot_layout = slot_layout,
        allow_cancel = true,
        cancel_label = "取消",
        meta = { item_id = inner_item_id, player_id = inner_player.id },
      }
    end,
  })
end

function handlers.handle_remote_dice(game, player, item_id, context)
  local dice_count = game:player_dice_count(player)
  return _run_item_choice_flow(game, player, item_id, context, {
    candidates = function()
      return { 1, 2, 3, 4, 5, 6 }
    end,
    ai_select = function(inner_game, inner_player, inner_item_id)
      local value, target_tile = auto_play_port.pick_remote_dice_value(inner_game, inner_player, dice_count)
      assert(value ~= nil, "missing remote dice value")
      local settled = settlement.execute(inner_game, inner_player, inner_item_id, function()
        return remote_dice.apply(inner_game, inner_player, dice_count, value)
      end, { consume = "before_apply" })
      if settled.ok and target_tile then
        -- #109:用卡提示只此一条(remote_dice.apply 已发);目标格走
        -- remote_dice_target(tip=false),只进行动日志,不再弹第二条提示。
        event_feed.publish(inner_game, {
          kind = event_kinds.remote_dice_target,
          text = inner_player.name .. " AI 设定遥控骰子前往 " .. target_tile.name .. " 点数 " .. number_utils.format_integer_part(value),
        })
      end
      return settled
    end,
    choice_spec = function(_, inner_player, inner_item_id, candidates)
      local options = {}
      local body_lines = {}
      for _, value in ipairs(candidates) do
        table.insert(options, { id = value, label = tostring(value) })
        table.insert(body_lines, "点数 " .. number_utils.format_integer_part(value))
      end
      return {
        kind = "remote_dice_value",
        route_key = "remote",
        pre_confirm_on_select = false,
        owner_role_id = inner_player.id,
        title = "遥控骰子：选择点数",
        body_lines = body_lines,
        options = options,
        allow_cancel = true,
        cancel_label = "放弃",
        meta = { player_id = inner_player.id, item_id = inner_item_id, dice_count = dice_count },
      }
    end,
  })
end

function handlers.handle_roadblock(game, player, item_id, context)
  context = context or {}
  return _run_item_choice_flow(game, player, item_id, context, {
    candidates = function(inner_game, inner_player, _, inner_context)
      if inner_context.is_computer_controlled then
        return roadblock.auto_candidates(inner_game, inner_player, 3)
      end
      return roadblock.manual_candidates(inner_game, inner_player, 3)
    end,
    on_empty = function(_, inner_player)
      -- migrated as DEV: internal candidate resolution failure, no player-visible state change occurred
      logger.info(inner_player.name .. " 无可放置路障的位置")
    end,
    ai_select = function(inner_game, inner_player, inner_item_id, candidates)
      local best = roadblock.pick_best(candidates)
      assert(best ~= nil and best.idx ~= nil, "missing roadblock target")
      return settlement.execute(inner_game, inner_player, inner_item_id, function()
        return roadblock.apply(inner_game, inner_player, best.idx)
      end, { consume = "before_apply" })
    end,
    choice_spec = function(inner_game, inner_player, inner_item_id, candidates)
      local flat_options = {}
      local body_lines = {}
      for _, cand in ipairs(candidates) do
        table.insert(flat_options, { id = cand.idx, label = cand.label })
        table.insert(body_lines, cand.label)
      end
      local options, slot_layout = board_query.arrange_target_options(inner_game.board, inner_player, flat_options)
      return {
        kind = "roadblock_target",
        route_key = "target",
        owner_role_id = inner_player.id,
        title = "路障卡：选择位置",
        body_lines = body_lines,
        options = options,
        target_slot_layout = slot_layout,
        allow_cancel = true,
        cancel_label = "放弃",
        meta = { player_id = inner_player.id, item_id = inner_item_id },
      }
    end,
  })
end

local demolish_items = {
  [item_ids.monster] = { title = "怪兽卡", injure = false },
  [item_ids.missile] = { title = "导弹卡", injure = true },
}

function handlers.handle_demolish(game, player, item_id, context)
  context = context or {}
  local cfg = assert(demolish_items[item_id], "missing demolish cfg: " .. tostring(item_id))
  return settlement.execute(game, player, item_id, function(commit)
    return demolish.use(game, player, 3, function()
      return commit()
    end, {
      item_id = item_id,
      injure = cfg.injure,
      title = cfg.title,
      is_computer_controlled = context.is_computer_controlled,
    })
  end, {
    consume = "applier_owned",
    fallback_reason = context.reject_reason_fallback,
  })
end

return handlers

