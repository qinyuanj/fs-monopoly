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

-- view_command 端口由 ui 自有字段持有（#209），开局装配写入；不经回合端口包，
-- 回合层 tick 时 resolve 回写 gameplay_loop_ports 不会让它失联。
local function _view_command_port(state)
  return state and state.view_command_port or nil
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

