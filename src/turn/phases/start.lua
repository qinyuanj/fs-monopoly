local logger = require("src.foundation.log")
local item_phase = require("src.rules.items.phase")
local item_auto_play_context = require("src.turn.policies.item_play_context")
local monopoly_event = require("src.foundation.events")
local timing = require("src.config.gameplay.timing")
local event_kinds = require("src.config.gameplay.event_kinds")
local event_feed = require("src.rules.ports.event_feed")
local dirty_tracker = require("src.state.dirty_tracker")
local phase_wait = require("src.turn.phases.phase_wait")

local function _clear_no_action_notice(turn)
  if not turn then
    return
  end
  turn.no_action_notice_active = false
  turn.no_action_notice_player_id = nil
  turn.no_action_notice_text = nil
end

local function _set_last_turn(game, player)
  game.last_turn = {
    player_id = player.id,
    player_name = player.name,
    skipped = false,
    rolls = nil,
    total = nil,
    move_result = nil,
    note = nil,
  }
end

local function _emit_turn_started(player, turn_count)
  monopoly_event.emit(monopoly_event.feedback.turn_started, {
    player = player,
    player_id = player.id,
    turn_count = turn_count,
  })
end

local function _skip_eliminated_player(game, player)
  if not player.eliminated then
    return nil
  end
  game.last_turn.note = "已出局，跳过"
  game.last_turn.skipped = true
  return "end_turn", { player = player }
end


local function _configure_detained_wait(game, turn, player)
  local detained_wait_seconds = timing.detained_turn_wait_seconds or 5.0
  -- 扣留剩余回合含当前回合:提示显示本回合扣减前的值,扣留中不显示 0。
  -- consume_detention_turn 在回合开始扣减内部计数,并返回含当前回合的显示值。
  local remaining_inclusive = game:consume_detention_turn(player)
  event_feed.publish(game, {
    kind = event_kinds.detained,
    text = player.name .. " 被扣留，剩余回合:" .. tostring(remaining_inclusive),
    tip = true,
  })
  game.last_turn.note = "被扣留"
  game.last_turn.skipped = true
  game.last_turn.stay_turns = game:detention_remaining(player)
  turn.detained_wait_active = detained_wait_seconds > 0
  turn.detained_wait_elapsed = 0
  turn.detained_wait_seconds = detained_wait_seconds
  turn.no_action_notice_active = true
  turn.no_action_notice_player_id = player.id
  turn.no_action_notice_text = "本回合无法行动"
  if detained_wait_seconds <= 0 then
    return "end_turn", { player = player }
  end
  return "detained_wait", { player = player }
end

local function _run_pre_action_item_phase(turn_mgr, player)
  local phase_res = item_phase.run(turn_mgr, "pre_action", {
    player = player,
    auto_play = item_auto_play_context.build(turn_mgr.game, player),
    next_state = "roll",
    next_args = { player = player },
  })
  if not (phase_res and phase_res.waiting) then
    return nil
  end
  return phase_wait.resolve_result(phase_res, "roll", player)
end

local function _phase_start(turn_mgr)
  local player = turn_mgr.game:current_player()
  local turn = turn_mgr.game.turn
  _clear_no_action_notice(turn)
  local tc = turn_mgr.game.turn.turn_count
  local current_index = turn_mgr.game.turn.current_player_index
  logger.info(
    "[Eggy]",
    "回合开始:",
    "current_player_index",
    tostring(current_index),
    "player_id",
    tostring(player.id)
  )
  _set_last_turn(turn_mgr.game, player)
  turn_mgr.game:increment_own_turn_started_count(player)
  _emit_turn_started(player, tc)
  local eliminated_state, eliminated_args = _skip_eliminated_player(turn_mgr.game, player)
  if eliminated_state ~= nil then
    return eliminated_state, eliminated_args
  end
  tc = tc + 1
  turn_mgr.game.turn.turn_count = tc
  dirty_tracker.mark(turn_mgr.game.dirty, "turn")
  if turn_mgr.game:detention_remaining(player) > 0 then
    return _configure_detained_wait(turn_mgr.game, turn, player)
  end

  local waiting_state, waiting_args = _run_pre_action_item_phase(turn_mgr, player)
  if waiting_state ~= nil then
    return "wait_action", { player = player, next_state = waiting_state, next_args = waiting_args }
  end

  return "wait_action", { player = player, next_state = "roll", next_args = { player = player } }
end

return _phase_start

