local M = {}

local function _resolved_ports(state)
  return state and (state._resolved_gameplay_loop_ports or state.gameplay_loop_ports) or nil
end

local function _sub_port(resolved, sub_key)
  return type(resolved) == "table" and resolved[sub_key] or nil
end

function M.resolve(state, sub_key, fallback)
  local sub = _sub_port(_resolved_ports(state), sub_key)
  if type(sub) == "table" then
    return sub
  end
  return fallback
end

return M

