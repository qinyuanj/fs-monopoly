local role_id_utils = require("src.foundation.identity")
local optional_action_choice = require("src.turn.optional_action_choice")

local optional_action_completion = {}

local function _indexed_current_player(game)
  local turn = game.turn
  local index = turn and turn.current_player_index or nil
  if index == nil or game.players == nil then
    return nil
  end
  return game.players[index]
end

local function _current_player(game)
  if game == nil then
    return nil
  end
  if type(game.current_player) == "function" then
    return game:current_player()
  end
  return _indexed_current_player(game)
end

local function _current_player_id(game)
  local player = _current_player(game)
  return role_id_utils.normalize(player and player.id or nil)
end

local function _game_pending_choice(game)
  return game and game.turn and game.turn.pending_choice or nil
end

local function _pending_choice(game, opts)
  if opts and opts.choice ~= nil then
    return opts.choice
  end
  return _game_pending_choice(game)
end

local function _is_blocked(opts)
  local gate_state = opts and opts.gate_state or nil
  return gate_state and gate_state.input_blocked == true
end

local function _rejected(reason, choice)
  local result = { ok = false, reason = reason }
  if reason ~= "no_optional_action" and choice ~= nil then
    result.choice = choice
  end
  return result
end

local function _choice_rejection_reason(choice, opts)
  if not optional_action_choice.is_optional_action_choice(choice) then
    return "no_optional_action"
  end
  if choice.allow_cancel == false then
    return "not_cancelable_optional_action"
  end
  if _is_blocked(opts) then
    return "blocked"
  end
  return nil
end

local function _actor_rejection_reason(game, actor_id, opts)
  if opts.require_actor == false then
    return nil
  end
  local normalized_actor_id = role_id_utils.normalize(actor_id)
  if normalized_actor_id == nil then
    return "missing_actor"
  end
  local current_player_id = _current_player_id(game)
  if current_player_id ~= nil and not role_id_utils.equals(normalized_actor_id, current_player_id) then
    return "not_current_player"
  end
  return nil
end

function optional_action_completion.can_complete_optional_action_phase(game, actor_id, state, opts)
  opts = opts or {}
  local choice = _pending_choice(game, opts)
  local choice_reason = _choice_rejection_reason(choice, opts)
  if choice_reason ~= nil then
    return _rejected(choice_reason, choice)
  end
  local actor_reason = _actor_rejection_reason(game, actor_id, opts)
  if actor_reason ~= nil then
    return _rejected(actor_reason, choice)
  end
  return { ok = true, choice = choice }
end

local function _build_choice_cancel_action(choice, actor_id, input_source)
  return {
    type = "choice_cancel",
    choice_id = choice.id,
    actor_role_id = role_id_utils.normalize(actor_id),
    input_source = input_source,
  }
end

local function _dispatch_with_game(game, action)
  if game and type(game.dispatch_action) == "function" then
    game:dispatch_action(action)
    return { status = "applied" }
  end
  return { status = "rejected" }
end

local function _dispatch_choice_cancel(game, action, dispatch)
  if type(dispatch) == "function" then
    return dispatch(action)
  end
  return _dispatch_with_game(game, action)
end

local function _completion_result(status, action, choice)
  local reason = nil
  if status ~= "applied" then
    reason = "dispatch_rejected"
  end
  return {
    ok = status == "applied",
    status = status,
    reason = reason,
    action = action,
    choice = choice,
  }
end

local function _dispatch_status(dispatch_result)
  return dispatch_result and dispatch_result.status or nil
end

function optional_action_completion.complete_optional_action_phase(game, actor_id, state, opts)
  opts = opts or {}
  local allowed = optional_action_completion.can_complete_optional_action_phase(game, actor_id, state, opts)
  if allowed.ok ~= true then
    return allowed
  end
  local action = _build_choice_cancel_action(allowed.choice, actor_id, opts.input_source)
  local dispatch_result = _dispatch_choice_cancel(game, action, opts.dispatch_choice_action)
  return _completion_result(_dispatch_status(dispatch_result), action, allowed.choice)
end

return optional_action_completion

