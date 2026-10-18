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

--[[ mutate4lua-manifest
version=4
projectHash=feb1bf3d37827424
scope.0.id=chunk:src/turn/phases/start.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=127
scope.0.semanticHash=a0ddc35de6c671c3
scope.1.id=function:_clear_no_action_notice
scope.1.kind=function
scope.1.startLine=11
scope.1.endLine=18
scope.1.semanticHash=e8faff86f8b27440
scope.2.id=function:_set_last_turn
scope.2.kind=function
scope.2.startLine=20
scope.2.endLine=30
scope.2.semanticHash=d46c8a8314e11100
scope.3.id=function:_emit_turn_started
scope.3.kind=function
scope.3.startLine=32
scope.3.endLine=38
scope.3.semanticHash=dfee11f778b2e8cd
scope.4.id=function:_skip_eliminated_player
scope.4.kind=function
scope.4.startLine=40
scope.4.endLine=47
scope.4.semanticHash=be6558e6c54f4dbf
scope.5.id=function:_configure_detained_wait
scope.5.kind=function
scope.5.startLine=50
scope.5.endLine=75
scope.5.semanticHash=43a4bf0cf4848d22
scope.6.id=function:_run_pre_action_item_phase
scope.6.kind=function
scope.6.startLine=77
scope.6.endLine=88
scope.6.semanticHash=e8ac17aeb4faec97
scope.7.id=function:_phase_start
scope.7.kind=function
scope.7.startLine=90
scope.7.endLine=124
scope.7.semanticHash=ed5b2171eccf50ff
]]
