local common = require("src.ui.ports.common")
local modal_ports = require("src.ui.ports.modal")
local anim_ports = require("src.ui.ports.anim")
local ui_sync_ports = require("src.ui.ports.ui_sync")
local event_log_ports = require("src.ui.ports.event_log")
local state_ports = require("src.ui.ports.state")
local clock_ports = require("src.ui.ports.clock")
local view_command_ports = require("src.ui.ports.view_command")
local actor_context_ports = require("src.ui.ports.actor_context")

local presentation_ports = {}

function presentation_ports.build()
  local debug = event_log_ports.build()
  return {
    modal = modal_ports.build(),
    anim = anim_ports.build(),
    ui_sync = ui_sync_ports.build(common),
    debug = debug,
    clock = clock_ports.build(),
    state = state_ports.build(),
    view_command = view_command_ports.build({ sync_event_log = debug.sync_event_log }),
    actor_context = actor_context_ports.build(),
  }
end

return presentation_ports

