local M = {}

function M.with_method(host_runtime, method_name)
  if not (host_runtime and type(host_runtime[method_name]) == "function") then
    return nil
  end
  return host_runtime
end

return M

