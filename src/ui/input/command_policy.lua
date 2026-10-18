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

--[[ mutate4lua-manifest
version=4
projectHash=2afbafe4becc2b7c
scope.0.id=chunk:src/ui/input/command_policy.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=73
scope.0.semanticHash=75350efb5ca9aa84
scope.1.id=function:_describe_ui_button
scope.1.kind=function
scope.1.startLine=9
scope.1.endLine=15
scope.1.semanticHash=c9780aa920a82d7f
scope.2.id=function:command_policy.describe
scope.2.kind=function
scope.2.startLine=17
scope.2.endLine=25
scope.2.semanticHash=d56f70e699aa37db
scope.3.id=function:_read
scope.3.kind=function
scope.3.startLine=27
scope.3.endLine=30
scope.3.semanticHash=837e31706e29c8d9
scope.4.id=function:command_policy.reason
scope.4.kind=function
scope.4.startLine=32
scope.4.endLine=34
scope.4.semanticHash=a9c1c4b362850cf7
scope.5.id=function:command_policy.is_view_command
scope.5.kind=function
scope.5.startLine=36
scope.5.endLine=38
scope.5.semanticHash=71b4071f2c7eb28d
scope.6.id=function:command_policy.dispatches_before_game
scope.6.kind=function
scope.6.startLine=40
scope.6.endLine=42
scope.6.semanticHash=71b4071f2c7eb28d
scope.7.id=function:command_policy.panel_id
scope.7.kind=function
scope.7.startLine=44
scope.7.endLine=46
scope.7.semanticHash=a9c1c4b362850cf7
scope.8.id=function:command_policy.requires_event_actor
scope.8.kind=function
scope.8.startLine=48
scope.8.endLine=50
scope.8.semanticHash=71b4071f2c7eb28d
scope.9.id=function:command_policy.uses_local_actor
scope.9.kind=function
scope.9.startLine=52
scope.9.endLine=54
scope.9.semanticHash=eaa6576c2f4ef972
scope.10.id=function:command_policy.is_optional_event_actor
scope.10.kind=function
scope.10.startLine=56
scope.10.endLine=58
scope.10.semanticHash=71b4071f2c7eb28d
scope.11.id=function:command_policy.port_handler
scope.11.kind=function
scope.11.startLine=60
scope.11.endLine=62
scope.11.semanticHash=a9c1c4b362850cf7
scope.12.id=function:command_policy.game_handler
scope.12.kind=function
scope.12.startLine=64
scope.12.endLine=66
scope.12.semanticHash=a9c1c4b362850cf7
scope.13.id=function:command_policy.is_item_slot_command
scope.13.kind=function
scope.13.startLine=68
scope.13.endLine=70
scope.13.semanticHash=71b4071f2c7eb28d
]]
