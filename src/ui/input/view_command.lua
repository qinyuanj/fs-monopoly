local view_command_dispatcher = {}
local panel_interrupt = require("src.ui.state.panel_interrupt")
local command_policy = require("src.ui.input.command_policy")
local logger = require("src.foundation.log")

local function _intent_panel_id(intent)
  return command_policy.panel_id(intent)
end

local function _blocks_panel_entry(state, intent)
  local panel_id = _intent_panel_id(intent)
  if panel_id == nil then
    return false
  end
  return panel_interrupt.block_entry(state, panel_id, intent.actor_role_id) == true
end

local function _view_command_port(state)
  local ports = state and state.gameplay_loop_ports or nil
  return ports and ports.view_command or nil
end

local function _resolve_port(state)
  local view_command = _view_command_port(state)
  if view_command == nil or type(view_command.dispatch) ~= "function" then
    return nil
  end
  return view_command
end

function view_command_dispatcher.dispatch(state, intent)
  if _blocks_panel_entry(state, intent) then
    return true
  end
  local view_command = _resolve_port(state)
  if view_command == nil then
    local intent_type = intent and intent.type
    logger.warn("view_command port missing, intent dropped:", tostring(intent_type))
    return false
  end
  return view_command.dispatch(state, intent) == true
end

return view_command_dispatcher

