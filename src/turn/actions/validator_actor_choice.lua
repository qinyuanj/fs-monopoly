local logger = require("src.foundation.log")
local number_utils = require("src.foundation.number")
local role_id_utils = require("src.foundation.identity")
local choice_contract = require("src.config.choice.contract")

local validator_actor_choice = {}

local function _current_player(game)
  return game and game.current_player and game:current_player() or nil
end

local function _resolve_current_player_role_id(game)
  local current = _current_player(game)
  return current and number_utils.to_integer(current.id) or nil
end

local function _resolve_choice_owner_role_id(game, choice)
  local owner_role_id = choice_contract.resolve_owner_role_id(choice)
  if owner_role_id ~= nil then
    return owner_role_id
  end
  return _resolve_current_player_role_id(game)
end

local function _action_type(action)
  return action and action.type or nil
end

local function _action_actor_role_id(action)
  return action and action.actor_role_id or nil
end

function validator_actor_choice.validate_choice_actor(game, action, choice)
  local actor_role_id = role_id_utils.normalize(_action_actor_role_id(action))
  if actor_role_id == nil then
    logger.warn("choice action missing actor_role_id:", tostring(_action_type(action)))
    return false
  end
  local owner_role_id = _resolve_choice_owner_role_id(game, choice)
  if owner_role_id ~= nil and not role_id_utils.equals(actor_role_id, owner_role_id) then
    logger.warn(
      "choice action blocked by actor check:",
      tostring(_action_type(action)),
      "actor_role_id=" .. tostring(actor_role_id),
      "owner_role_id=" .. tostring(owner_role_id)
    )
    return false
  end
  return true
end

function validator_actor_choice.validate_choice_id(action, choice)
  if not action or not choice then
    return false
  end
  if not action.choice_id or action.choice_id ~= choice.id then
    logger.warn(
      "choice action mismatch:",
      tostring(action.type),
      "action_choice_id=" .. tostring(action.choice_id),
      "pending_choice_id=" .. tostring(choice.id)
    )
    return false
  end
  return true
end

local function _warn_missing_choice(action)
  logger.warn("choice action without pending choice:", tostring(action and action.type))
end

function validator_actor_choice.validate_choice_action(game, action, choice)
  if not choice or not choice.id then
    _warn_missing_choice(action)
    return false, "missing_choice"
  end
  if not validator_actor_choice.validate_choice_actor(game, action, choice) then
    return false, "choice_actor_mismatch"
  end
  if not validator_actor_choice.validate_choice_id(action, choice) then
    return false, "choice_id_mismatch"
  end
  return true
end

return validator_actor_choice

