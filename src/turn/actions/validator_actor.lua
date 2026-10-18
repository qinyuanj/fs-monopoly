local logger = require("src.foundation.log")
local role_id_utils = require("src.foundation.identity")

local validator_actor = {}

-- 只有 next 是回合绑定的 ui_button。道具槽点击已不是 ui_button——它的行动者是
-- 「点击者」而非「当前回合玩家」,拿这条规则去卡它会把他人回合的点击静默拒掉。
local function _is_turn_bound_ui_button(action_id)
  return action_id == "next"
end

local function _current_turn_player(game)
  local current_index = game.turn.current_player_index
  return current_index and game.players and game.players[current_index] or nil
end

local function _resolve_current_turn_role_id(game)
  local current_player = _current_turn_player(game)
  return role_id_utils.normalize(current_player and current_player.id or nil)
end

local function _validate_actor_matches_current(action, actor_role_id, current_role_id)
  if actor_role_id == nil then
    logger.warn("ui_button missing actor_role_id:", tostring(action.id))
    return false
  end
  if current_role_id == nil then
    logger.warn("ui_button missing current_role_id:", tostring(action.id))
    return false
  end
  if not role_id_utils.equals(actor_role_id, current_role_id) then
    logger.warn(
      "ui_button blocked by actor check:",
      tostring(action.id),
      "actor_role_id=" .. tostring(actor_role_id),
      "current_role_id=" .. tostring(current_role_id)
    )
    return false
  end
  return true
end

function validator_actor.validate_actor_role(game, action)
  if not _is_turn_bound_ui_button(action and action.id) then
    return true
  end
  assert(game ~= nil and game.turn ~= nil, "missing game.turn")
  local current_role_id = _resolve_current_turn_role_id(game)
  local actor_role_id = role_id_utils.normalize(action.actor_role_id)
  return _validate_actor_matches_current(action, actor_role_id, current_role_id)
end

return validator_actor

