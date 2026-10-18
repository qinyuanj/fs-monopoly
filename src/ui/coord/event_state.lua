local runtime = require("src.ui.render.support.runtime_ui")
local role_id_utils = require("src.foundation.identity")

local ui_event_state = {}

local function _resolve_client_role_id()
  local role = runtime.get_client_role()
  return runtime.resolve_role_id(role)
end

local function _read_event_log_flag(ui, role_id)
  local by_role = ui and ui.debug_log_enabled_by_role or nil
  if type(by_role) ~= "table" then
    return false
  end
  return role_id_utils.read(by_role, role_id) == true
end

-- role_id 省略时回落到当前客户端角色；解析不出角色一律视为未开启。
function ui_event_state.resolve_event_log_enabled(state, role_id)
  local ui = state and state.ui
  if role_id == nil then
    role_id = _resolve_client_role_id()
  end
  role_id = role_id_utils.normalize(role_id)
  if role_id == nil then
    return false
  end
  return _read_event_log_flag(ui, role_id)
end

return ui_event_state

