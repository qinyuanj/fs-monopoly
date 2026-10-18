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

--[[ mutate4lua-manifest
version=4
projectHash=baacd93da53c172b
scope.0.id=chunk:src/ui/coord/event_state.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=48
scope.0.semanticHash=a5b38db0e202e97b
scope.1.id=function:_has_active_modal
scope.1.kind=function
scope.1.startLine=6
scope.1.endLine=8
scope.1.semanticHash=24b9d911627e97ee
scope.2.id=function:ui_event_state.is_base_screen_active
scope.2.kind=function
scope.2.startLine=10
scope.2.endLine=19
scope.2.semanticHash=e6147e51d749d6af
scope.3.id=function:_resolve_client_role_id
scope.3.kind=function
scope.3.startLine=21
scope.3.endLine=24
scope.3.semanticHash=f62ee5af98cbc6a1
scope.4.id=function:_read_event_log_flag
scope.4.kind=function
scope.4.startLine=26
scope.4.endLine=32
scope.4.semanticHash=2c14530507c8d8df
scope.5.id=function:ui_event_state.resolve_event_log_enabled
scope.5.kind=function
scope.5.startLine=35
scope.5.endLine=45
scope.5.semanticHash=f185084f57734972
]]
