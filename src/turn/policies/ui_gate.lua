-- The UI sync gate is optional: headless lanes and the no-UI gameplay guard run
-- without ui_sync ports installed. Both the action validator and the auto-play
-- context need the same "ask the port if it is there, otherwise no gate" rule,
-- so it lives here rather than being restated at each call site.
local ui_gate = {}

function ui_gate.resolve(state, ui_sync_ports)
  if ui_sync_ports and type(ui_sync_ports.resolve_ui_gate) == "function" then
    return ui_sync_ports.resolve_ui_gate(state)
  end
  return nil
end

return ui_gate

