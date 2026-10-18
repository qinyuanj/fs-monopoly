local tip_queue = require("src.foundation.tips")
local action_button_wait = require("src.turn.policies.action_button_wait")
local action_button_timer = require("src.turn.policies.action_button_timer")

local turn_timer_policy = {}

turn_timer_policy.is_action_button_wait_active = action_button_wait.is_action_button_wait_active
turn_timer_policy.update_action_button_timer = action_button_timer.update_action_button_timer

local function _complete_wait(turn, active_key, elapsed_key, step_turn, game)
  turn[active_key] = false
  turn[elapsed_key] = 0
  step_turn(game)
end

local function _active_turn(game, active_key)
  local turn = game.turn
  if not (turn and turn[active_key]) then
    return nil
  end
  return turn
end

local function _resolve_active_wait(game, state, active_key, timeout_key)
  if not (game and state) then
    return nil
  end
  local turn = _active_turn(game, active_key)
  if turn == nil then
    return nil
  end
  return turn, turn[timeout_key] or 0
end

local function _completion_vetoed(before_complete, turn, timeout)
  return before_complete and before_complete(turn, timeout) == false
end

local function _wait_timer(game, state, dt, step_turn, active_key, elapsed_key, timeout_key, before_complete)
  local turn, timeout = _resolve_active_wait(game, state, active_key, timeout_key)
  if turn == nil then
    return
  end

  local elapsed = action_button_timer.resolve_elapsed(turn[elapsed_key], dt)
  if timeout <= 0 then
    _complete_wait(turn, active_key, elapsed_key, step_turn, game)
    return
  end
  if elapsed < timeout then
    turn[elapsed_key] = elapsed
    return
  end

  if _completion_vetoed(before_complete, turn, timeout) then
    return
  end

  _complete_wait(turn, active_key, elapsed_key, step_turn, game)
end

function turn_timer_policy.update_detained_wait_timer(game, state, dt, step_turn)
  _wait_timer(game, state, dt, step_turn,
    "detained_wait_active", "detained_wait_elapsed", "detained_wait_seconds", nil)
end

local function _inter_turn_before_complete(turn, timeout)
  turn.inter_turn_wait_elapsed = timeout
  if tip_queue.has_blocking_pending("inter_turn") then
    return false
  end
  return true
end

function turn_timer_policy.update_inter_turn_wait_timer(game, state, dt, step_turn)
  _wait_timer(game, state, dt, step_turn,
    "inter_turn_wait_active", "inter_turn_wait_elapsed", "inter_turn_wait_seconds",
    _inter_turn_before_complete)
end

return turn_timer_policy

