local runtime = require("src.ui.render.support.runtime_ui")

local resolver = {}

local function _resolve_role_id_from_event(data)
  local role = data and data.role or nil
  return runtime.resolve_role_id(role)
end

local function _resolve_client_role_id()
  return runtime.resolve_role_id(runtime.get_client_role())
end

-- 解析链只到 client_role 为止(#341):事件解析不出身份即返回 nil(静默),不得
-- 把 A 的点击当成 B 的。「上一次点击者缓存」随 #601 整体退役——既不读也不写,
-- state 上不再出现 local_actor_role_id。
function resolver.resolve_from_event(state, data)
  local role_id = _resolve_role_id_from_event(data)
  if role_id ~= nil then
    return role_id
  end
  return _resolve_client_role_id()
end

resolver.resolve_turn_bound = resolver.resolve_from_event

return resolver

