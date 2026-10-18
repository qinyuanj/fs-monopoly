local host_runtime_ports = require("src.ui.seams.host_runtime")

local M = {}

function M.from_deps(deps)
  if deps and deps.host_runtime then
    return deps.host_runtime
  end
  return host_runtime_ports
end

function M.from_state(state_or_scene, deps)
  local resolved_deps = deps or (state_or_scene and state_or_scene.presentation_runtime) or nil
  return M.from_deps(resolved_deps)
end

return M

