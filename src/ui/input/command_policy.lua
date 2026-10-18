local definitions = require("src.ui.input.command_definitions")

local command_policy = {}

local COMMANDS = definitions.COMMANDS
local UI_BUTTONS = definitions.UI_BUTTONS
local GENERIC_UI_BUTTON = definitions.GENERIC_UI_BUTTON

local function _describe_ui_button(intent)
  local action_id = intent and intent.id
  if UI_BUTTONS[action_id] ~= nil then
    return UI_BUTTONS[action_id]
  end
  return GENERIC_UI_BUTTON
end

function command_policy.describe(intent)
  if type(intent) ~= "table" then
    return nil
  end
  if intent.type == "ui_button" then
    return _describe_ui_button(intent)
  end
  return COMMANDS[intent.type]
end

local function _read(intent, key)
  local command = command_policy.describe(intent)
  return command and command[key] or nil
end

function command_policy.reason(intent)
  return _read(intent, "reason")
end

function command_policy.dispatches_before_game(intent)
  return _read(intent, "dispatch_before_game") == true
end

function command_policy.panel_id(intent)
  return _read(intent, "panel_id")
end

function command_policy.requires_event_actor(intent)
  return _read(intent, "requires_event_actor") == true
end

function command_policy.uses_local_actor(intent)
  return _read(intent, "actor_source") == "local"
end

function command_policy.is_optional_event_actor(intent)
  return _read(intent, "optional_event_actor") == true
end

function command_policy.port_handler(intent)
  return _read(intent, "port_handler")
end

function command_policy.game_handler(intent)
  return _read(intent, "game_handler")
end

function command_policy.is_item_slot_command(intent)
  return _read(intent, "item_slot") == true
end

return command_policy

