local timing = require("src.config.gameplay.timing")
local number_utils = require("src.foundation.number")

local tick_ui_gate = {}

local _fallback_gate = {
  input_blocked = false,
  choice_active = false,
  market_active = false,
  popup_active = false,
  popup_seq = nil,
  popup_auto_close_seconds = nil,
  popup_owner_index = nil,
}

local function _ports_ui_sync(state)
  return state and state.gameplay_loop_ports and state.gameplay_loop_ports.ui_sync or nil
end

local function _resolve_ui_gate(state, resolver)
  if resolver and type(resolver.resolve_ui_gate) == "function" then
    local gate = resolver.resolve_ui_gate(state)
    if type(gate) == "table" then
      return gate
    end
  end
  return nil
end

function tick_ui_gate.resolve_ui_gate(state, ui_sync_ports)
  local resolver = ui_sync_ports or _ports_ui_sync(state)
  local gate = _resolve_ui_gate(state, resolver)
  if gate ~= nil then
    return gate
  end
  return _fallback_gate
end

function tick_ui_gate.resolve_modal_timeout_seconds(state, ui_sync_ports)
  local gate = tick_ui_gate.resolve_ui_gate(state, ui_sync_ports)
  local auto_close_seconds = gate.popup_auto_close_seconds
  if auto_close_seconds ~= nil and number_utils.is_numeric(auto_close_seconds) and auto_close_seconds > 0 then
    return auto_close_seconds
  end
  return timing.popup_auto_close_seconds
end

return tick_ui_gate

