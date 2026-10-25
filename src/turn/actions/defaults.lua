local runtime_ports = require("src.foundation.ports.runtime_ports")

local next_turn_cooldown = 0.4

local default_ui_sync_ports = {
  resolve_ui_gate = function()
    return nil
  end,
}

-- 回合层唯一的基础 clock 组（#206）：就是 foundation runtime_ports 的四个端口，
-- 每次调用才解析 configure 装配的实现，未装配宿主时钟时都返回 0。
-- state 没有回合端口时 context 用它兜底，turn/loop/ports 的基础 clock 组也复用它。
local default_clock_ports = {
  wall_now_seconds = runtime_ports.wall_now_seconds,
  wall_diff_seconds = runtime_ports.wall_diff_seconds,
  cpu_now_seconds = runtime_ports.cpu_now_seconds,
  cpu_diff_seconds = runtime_ports.cpu_diff_seconds,
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

