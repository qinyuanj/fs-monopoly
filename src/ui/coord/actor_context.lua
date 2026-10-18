local runtime = require("src.ui.render.support.runtime_ui")
local host_roles = require("src.ui.seams.host_roles")
local role_id_utils = require("src.foundation.identity")

local actor_context = {}

local function _find_role_in_roster(role_id)
  local roles = host_roles.resolve_roles()
  if type(roles) ~= "table" then
    return nil
  end
  for _, role in ipairs(roles) do
    if role_id_utils.equals(runtime.resolve_role_id(role), role_id) then
      return role
    end
  end
  return nil
end

-- 宿主名册里找不到时退化成一个只认得自己 id 的最小 role stub。
function actor_context.resolve_role_by_id(role_id)
  role_id = role_id_utils.normalize(role_id)
  if role_id == nil then
    return runtime.get_client_role()
  end
  local role = _find_role_in_roster(role_id)
  if role ~= nil then
    return role
  end
  local resolved = host_roles.resolve_role_with(role_id)
  if resolved ~= nil then
    return resolved
  end
  return {
    get_roleid = function()
      return role_id
    end,
  }
end

return actor_context

