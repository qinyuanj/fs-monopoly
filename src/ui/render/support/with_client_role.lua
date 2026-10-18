local function with_client_role(runtime, role, fn)
  assert(runtime ~= nil, "missing runtime")
  assert(type(fn) == "function", "missing fn")
  if type(runtime.with_client_role) == "function" then
    return runtime.with_client_role(role, fn)
  end
  if type(runtime.set_client_role) ~= "function" then
    return fn()
  end
  runtime.set_client_role(role)
  local ok, err = pcall(fn)
  runtime.set_client_role(nil)
  if not ok then
    error(err)
  end
end

return with_client_role

