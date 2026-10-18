local debug_flags = require("src.config.gameplay.debug_flags")
local runtime_state = require("src.state.runtime")

local turn_role_control_policy = {}

local function _resolve_role_control_lock_enabled(game)
  if debug_flags.role_control_lock_enabled ~= true then
    return false
  end
  if not game or game.finished then
    return false
  end
  return true
end

local function _state_ports(ports)
  return ports and ports.state or nil
end

local function _apply_lock_enabled(state_ports, state, enabled, turn_runtime)
  if enabled then
    state_ports.apply_role_control_lock(state, true)
    turn_runtime.role_control_lock_active = true
    return
  end
  if turn_runtime.role_control_lock_active then
    state_ports.apply_role_control_lock(state, false)
    turn_runtime.role_control_lock_active = false
  end
end

function turn_role_control_policy.sync(game, state, ports)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  local state_ports = _state_ports(ports)
  if not state or not state_ports or not state_ports.apply_role_control_lock then
    return
  end

  _apply_lock_enabled(state_ports, state, _resolve_role_control_lock_enabled(game), turn_runtime)
end

return turn_role_control_policy

