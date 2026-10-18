local choice_route_policy = require("src.config.choice.route_policy")
local choice_options = require("src.ui.view.choice_options")
local optional_action_choice = require("src.turn.optional_action_choice")

local M = {}

M.resolve_option_id = choice_options.resolve_option_id
M.resolve_option_label = choice_options.resolve_option_label
M.resolve_option_by_id = choice_options.resolve_option_by_id
M.resolve_option_label_by_id = choice_options.resolve_option_label_by_id

local function _fallback_confirm_body(option_label)
  if option_label and option_label ~= "" then
    return "你选的是：" .. tostring(option_label)
  end
  return "请再确认一次"
end

local function _non_empty_string(value)
  return type(value) == "string" and value ~= ""
end

function M.resolve_secondary_confirm_title(choice, _game, _source_screen, option_id)
  local option = M.resolve_option_by_id(choice, option_id)
  if option and _non_empty_string(option.confirm_title) then
    return option.confirm_title
  end
  if choice and _non_empty_string(choice.confirm_title) then
    return choice.confirm_title
  end
  return "请确认"
end

local function _option_confirm_body(choice, option_id)
  local option = M.resolve_option_by_id(choice, option_id)
  if option and _non_empty_string(option.confirm_body) then
    return option.confirm_body
  end
  return nil
end

local function _choice_confirm_body(choice)
  if _non_empty_string(choice.confirm_body) then
    return choice.confirm_body
  end
  return nil
end

local function _resolved_option_label(choice, option_id, option_label)
  return option_label or M.resolve_option_label_by_id(choice, option_id)
end

function M.resolve_secondary_confirm_body(choice, _game, _source_screen, option_id, option_label)
  if not choice then
    return _fallback_confirm_body(option_label)
  end
  local body = _option_confirm_body(choice, option_id) or _choice_confirm_body(choice)
  if body ~= nil then
    return body
  end
  return _fallback_confirm_body(_resolved_option_label(choice, option_id, option_label))
end

function M.build_secondary_confirm_body(choice, game, selected_option_id)
  return M.resolve_secondary_confirm_body(
    choice,
    game,
    "secondary_confirm",
    selected_option_id,
    M.resolve_option_label_by_id(choice, selected_option_id)
  )
end

function M.uses_item_slots(choice)
  return choice ~= nil and choice.uses_item_slots == true
end

function M.requires_item_slot_pre_confirm(choice)
  return choice ~= nil and choice.pre_confirm_before_slot_pick == true
end

function M.is_optional_action_choice(choice)
  return optional_action_choice.is_optional_action_choice(choice)
end

function M.is_cancelable_optional_action_choice(choice)
  return optional_action_choice.is_cancelable_optional_action_choice(choice)
end

function M.is_pre_action_item_phase_passive(choice)
  return optional_action_choice.is_pre_action_item_phase_passive(choice)
end

function M.is_item_target_selection_choice(choice)
  return optional_action_choice.is_item_target_selection_choice(choice)
end

function M.is_base_cancel_choice(choice)
  return optional_action_choice.is_base_cancel_choice(choice)
end

M.resolve_screen_key = choice_route_policy.resolve

return M

