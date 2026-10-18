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

--[[ mutate4lua-manifest
version=4
projectHash=22909d715d291cc4
scope.0.id=chunk:src/ui/ports/init.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=101
scope.0.semanticHash=2cfff9d3759ff8f7
scope.1.id=function:presentation_ports.build
scope.1.kind=function
scope.1.startLine=82
scope.1.endLine=94
scope.1.semanticHash=b8b3c06918de14eb
scope.2.id=function:presentation_ports.describe_boundary_contract
scope.2.kind=function
scope.2.startLine=96
scope.2.endLine=98
scope.2.semanticHash=1136505bd37c301e
]]
