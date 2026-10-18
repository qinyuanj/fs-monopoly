local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local with_client_role = require("src.ui.render.support.with_client_role")

local M = {}

function M.resolve_runtime(state)
  local presentation_runtime = state and state.presentation_runtime or nil
  return (presentation_runtime and presentation_runtime.runtime) or runtime_ui
end

function M.with_owner_role(state, role_id, fn)
  local role = runtime_ports.resolve_role(role_id)
  if role == nil then
    return fn()
  end
  return with_client_role(M.resolve_runtime(state), role, fn)
end

return M

