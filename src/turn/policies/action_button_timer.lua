local constants = require("src.config.content.constants")
local action_button_wait = require("src.turn.policies.action_button_wait")
local afk_signal = require("src.turn.policies.afk_signal")
local control = require("src.player.control")

local action_button_timer = {}

local function _reset_action_button(state)
  state.action_button_active = false
  state.action_button_elapsed = 0
  state.action_button_player_id = nil
end

function action_button_timer.resolve_elapsed(elapsed, dt)
  return (elapsed or 0) + (dt or 0)
end

local function _current_player_index(game)
  return game and game.turn and game.turn.current_player_index or nil
end

local function _player_at_index(game, current_index)
  return current_index and game.players and game.players[current_index] or nil
end

local function _resolve_current_player(game)
  return _player_at_index(game, _current_player_index(game))
end

local function _should_track_action_button_for_player(game, player)
  if control.is_computer_controlled(player) then
    return true
  end
  local phase = game and game.turn and game.turn.phase or nil
  return phase == "wait_action"
end

local function _update_elapsed_timer(state, dt, timeout)
  local elapsed = action_button_timer.resolve_elapsed(state.action_button_elapsed, dt)
  if elapsed < timeout then
    state.action_button_elapsed = elapsed
    return true
  end
  return false
end

local function _handle_timeout_elapsed(state, game, ctx)
  state.action_button_elapsed = 0
  local current_player = _resolve_current_player(game)
  if not current_player then
    return
  end
  if afk_signal.is_timeout_eligible(current_player) then
    afk_signal.on_timeout_fallback(game, state, current_player.id, "action_button")
  end
  if ctx.dispatch_next then
    ctx.dispatch_next(current_player.id, "timeout")
  end
end

local function _resolve_active_timeout(game, state, ports)
  if not action_button_wait.is_action_button_wait_active(game, state, ports) then
    return nil
  end
  local timeout = constants.action_timeout_seconds or 0
  if timeout <= 0 then
    return nil
  end
  return timeout
end

local function _resolve_tracked_player(game)
  local current_player = _resolve_current_player(game)
  if not current_player then
    return nil
  end
  if not _should_track_action_button_for_player(game, current_player) then
    return nil
  end
  return current_player
end

local function _resolve_action_timer_context(ctx)
  local state = ctx and ctx.state
  if not state then
    return nil
  end
  local game = ctx.game
  local timeout = _resolve_active_timeout(game, state, ctx.ports)
  if not timeout then
    return nil
  end
  local current_player = _resolve_tracked_player(game)
  if not current_player then
    return nil
  end
  return state, game, timeout, current_player
end

-- 上下文不成立时，仍要把 ctx 上挂着的 state 复位。
local function _reset_from_ctx(ctx)
  local state = ctx and ctx.state
  if state then
    _reset_action_button(state)
  end
end

function action_button_timer.update_action_button_timer(ctx)
  local state, game, timeout, current_player = _resolve_action_timer_context(ctx)
  if not state then
    _reset_from_ctx(ctx)
    return
  end

  if state.action_button_player_id ~= current_player.id then
    state.action_button_player_id = current_player.id
    state.action_button_elapsed = 0
  end

  state.action_button_active = true

  if _update_elapsed_timer(state, ctx.dt, timeout) then
    return
  end

  _handle_timeout_elapsed(state, game, ctx)
end

return action_button_timer

