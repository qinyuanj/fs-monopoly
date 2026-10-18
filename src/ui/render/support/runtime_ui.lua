local runtime_ports = require("src.foundation.ports.runtime_ports")
local role_id_utils = require("src.foundation.identity")

local runtime = {}

-- #541:宿主 traceback 全局不保证拼入原始 msg(真机实测只剩空
-- "stack traceback:"),错误正文必须由本侧 tostring 保留,traceback 只做附录。
local function _traceback(err)
  local message = tostring(err)
  if type(traceback) == "function" then
    return message .. "\n" .. tostring(traceback(message))
  end
  return message
end

-- role 作用域内的失败带目标 role 标识,事后仅凭日志可分辨是哪个角色的
-- 推送炸了;role 为 nil(全局推送)时不加前缀。
local function _role_error_prefix(role)
  if role == nil then
    return ""
  end
  local role_id = runtime.resolve_role_id(role)
  if role_id == nil then
    role_id = tostring(role)
  end
  return "[role=" .. tostring(role_id) .. "] "
end

function runtime.set_client_role(role)
  if UIManager then
    UIManager.client_role = role
  end
end

function runtime.get_client_role()
  if UIManager then
    return UIManager.client_role
  end
  return nil
end

function runtime.resolve_role_id(role)
  if not role or not role.get_roleid then
    return nil
  end
  local ok, raw_role_id = pcall(role.get_roleid)
  if not ok then
    return nil
  end
  return role_id_utils.normalize(raw_role_id)
end

function runtime.with_client_role(role, fn, ...)
  assert(type(fn) == "function", "missing fn")
  local previous_role = UIManager and UIManager.client_role or nil
  runtime.set_client_role(role)
  local ok, result = xpcall(fn, _traceback, ...)
  runtime.set_client_role(previous_role)
  if not ok then
    error(_role_error_prefix(role) .. result)
  end
  return result
end

function runtime.for_each_role_or_global(fn)
  assert(type(fn) == "function", "missing fn")
  local roles = runtime_ports.resolve_roles()
  if type(roles) == "table" and #roles > 0 then
    for _, role in ipairs(roles) do
      runtime.with_client_role(role, fn, role)
    end
    return
  end
  runtime.with_client_role(nil, fn, nil)
end

function runtime.query_nodes(name)
  assert(name ~= nil, "missing ui node name")
  assert(UIManager ~= nil and UIManager.query_nodes_by_name ~= nil, "missing UIManager.query_nodes_by_name")
  local nodes = UIManager.query_nodes_by_name(name)
  assert(nodes ~= nil and nodes[1] ~= nil, "missing ui node: " .. tostring(name))
  return nodes
end

function runtime.query_node(name)
  local nodes = runtime.query_nodes(name)
  return nodes[1]
end

local function _apply_texture_via_methods(node, image_key, methods)
  assert(node ~= nil, "missing image node")
  assert(image_key ~= nil, "missing image key")
  for _, method_name in ipairs(methods) do
    if node[method_name] then
      node[method_name](node, image_key)
      return
    end
  end
  node.image_texture = image_key
end

function runtime.set_node_texture_keep_size(node, image_key)
  _apply_texture_via_methods(node, image_key, { "set_texture_keep_size" })
end

function runtime.set_node_texture_native_size(node, image_key)
  _apply_texture_via_methods(node, image_key, { "set_texture_native_size", "set_texture_keep_size" })
end

return runtime

