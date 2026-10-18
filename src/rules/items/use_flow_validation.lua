local availability = require("src.rules.items.availability")
local inventory = require("src.rules.items.inventory")
local flow_context = require("src.rules.items.use_flow_context")
local flow_result = require("src.rules.items.use_flow_result")

local validation = {}

local function _reject_missing_begin_subject(game, player, item_id)
  if game == nil then
    return flow_result.rejected("missing_game")
  end
  if player == nil then
    return flow_result.rejected("missing_actor", { item_id = item_id })
  end
  return nil
end

local function _reject_unusable_item(player, item_id)
  if inventory.cfg(item_id) == nil then
    return flow_result.rejected("missing_item_cfg", { actor = player, actor_id = player.id, item_id = item_id })
  end
  if inventory.find_index(player, item_id) == nil then
    return flow_result.rejected("item_not_in_inventory", { actor = player, actor_id = player.id, item_id = item_id })
  end
  return nil
end

local function _reject_phase_unavailable(game, player, item_id, phase)
  if phase == nil then
    return nil
  end
  local can_offer, deny_reason = availability.can_offer_in_phase(game, player, item_id, phase)
  if can_offer == true then
    return nil
  end
  return flow_result.rejected(deny_reason or "item_unavailable", {
    actor = player,
    actor_id = player.id,
    item_id = item_id,
  })
end

function validation.validate_begin(game, player, item_id, use_context)
  local invalid = _reject_missing_begin_subject(game, player, item_id)
  if invalid ~= nil then return invalid end

  invalid = _reject_unusable_item(player, item_id)
  if invalid ~= nil then return invalid end

  invalid = _reject_phase_unavailable(game, player, item_id, use_context.phase)
  if invalid ~= nil then return invalid end

  return nil
end

local function _option_matches(option, option_id)
  return option == option_id
    or tostring(option) == tostring(option_id)
    or (type(option) == "table" and (option.id == option_id or tostring(option.id) == tostring(option_id)))
end

local function _choice_has_option(choice, option_id)
  for _, option in ipairs(choice and choice.options or {}) do
    if _option_matches(option, option_id) then
      return true
    end
  end
  return false
end

local function _reject_missing_choice_subject(game, choice, action)
  if game == nil then
    return flow_result.rejected("missing_game")
  end
  if type(choice) ~= "table" then
    return flow_result.rejected("missing_choice")
  end
  if action == nil then
    return flow_result.rejected("missing_action", { choice = choice })
  end
  return nil
end

local function _reject_choice_mismatch(choice, action)
  if action.choice_id ~= nil and choice.id ~= nil and tostring(action.choice_id) ~= tostring(choice.id) then
    return flow_result.rejected("choice_mismatch", { choice = choice })
  end
  return nil
end

local function _resolve_choice_actor(game, choice, action, meta)
  local player = flow_context.resolve_actor(game, meta.player_id)
  if player == nil then
    return nil, flow_result.rejected("missing_actor", { choice = choice })
  end
  if action.actor_role_id ~= nil and tostring(action.actor_role_id) ~= tostring(player.id) then
    return nil, flow_result.rejected("actor_mismatch", { actor = player, actor_id = player.id, choice = choice })
  end
  return player, nil
end

local function _reject_item_mismatch(player, choice, meta, use_context)
  if use_context.item_id ~= nil and meta.item_id ~= nil and tostring(use_context.item_id) ~= tostring(meta.item_id) then
    return flow_result.rejected("item_mismatch", { actor = player, actor_id = player.id, choice = choice })
  end
  return nil
end

local function _reject_invalid_option(player, choice, action)
  if not _choice_has_option(choice, action.option_id) then
    return flow_result.rejected("invalid_option", { actor = player, actor_id = player.id, choice = choice })
  end
  return nil
end

local function _validate_choice_subject(game, choice, action)
  local invalid = _reject_missing_choice_subject(game, choice, action)
  if invalid ~= nil then return nil, invalid end

  invalid = _reject_choice_mismatch(choice, action)
  if invalid ~= nil then return nil, invalid end

  return choice.meta or {}, nil
end

local function _validate_choice_target(game, choice, action, use_context, meta)
  local player, invalid = _resolve_choice_actor(game, choice, action, meta)
  if invalid ~= nil then return nil, invalid end

  invalid = _reject_item_mismatch(player, choice, meta, use_context)
  if invalid ~= nil then return nil, invalid end

  invalid = _reject_invalid_option(player, choice, action)
  if invalid ~= nil then return nil, invalid end

  return player, nil
end

function validation.validate_choice(game, choice, action, use_context)
  local meta, invalid = _validate_choice_subject(game, choice, action)
  if invalid ~= nil then return nil, nil, nil, invalid end

  local player
  player, invalid = _validate_choice_target(game, choice, action, use_context, meta)
  if invalid ~= nil then return nil, nil, nil, invalid end

  return meta, player, meta.item_id or use_context.item_id, nil
end

return validation

