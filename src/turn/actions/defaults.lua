local number_utils = require("src.foundation.number")

local next_turn_cooldown = 0.4

local default_ui_sync_ports = {
  resolve_ui_gate = function()
    return nil
  end,
}

local default_clock_ports = {
  wall_now_seconds = function()
    return 0
  end,
  wall_diff_seconds = number_utils.diff_or_zero,
}

local function _loop_ports(state)
  return state and (state._resolved_gameplay_loop_ports or state.gameplay_loop_ports) or nil
end

local function _group_of(resolved, key)
  return type(resolved) == "table" and resolved[key] or nil
end

local function resolve_port_group(state, key)
  local group = _group_of(_loop_ports(state), key)
  if type(group) == "table" then
    return group
  end
  return nil
end

return {
  next_turn_cooldown = next_turn_cooldown,
  default_ui_sync_ports = default_ui_sync_ports,
  default_clock_ports = default_clock_ports,
  resolve_port_group = resolve_port_group,
}

