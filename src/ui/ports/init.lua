local common = require("src.ui.ports.common")
local modal_ports = require("src.ui.ports.modal")
local anim_ports = require("src.ui.ports.anim")
local ui_sync_ports = require("src.ui.ports.ui_sync")
local event_log_ports = require("src.ui.ports.event_log")
local state_ports = require("src.ui.ports.state")
local view_command_ports = require("src.ui.ports.view_command")

local presentation_ports = {}

-- 回合端口包：只含回合层声明的分组（契约见 src/turn/loop/ports.lua）。
-- 不提供 clock：回合层基础 clock 直接委派 foundation runtime_ports（#210）。
function presentation_ports.build()
  local debug = event_log_ports.build()
  return {
    modal = modal_ports.build(),
    anim = anim_ports.build(),
    ui_sync = ui_sync_ports.build(common),
    debug = debug,
    state = state_ports.build(),
  }
end

-- view_command 是 ui 自有端口，不进回合端口包（#209）：开局装配写到
-- state.view_command_port，由 src/ui/input/view_command.lua 读取。
-- toggle_action_log 复用同一份回合端口包里的 debug.sync_event_log。
function presentation_ports.build_view_command(turn_ports)
  local debug = turn_ports and turn_ports.debug or nil
  return view_command_ports.build({ sync_event_log = debug and debug.sync_event_log or nil })
end

return presentation_ports
