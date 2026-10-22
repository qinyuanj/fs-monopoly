local runtime_ports = {}

local configured = nil

local function _resolve_port(name)
  if configured and configured[name] ~= nil then
    return configured[name]
  end
  return nil
end

-- Build a port that forwards its arguments to the configured implementation
-- and returns `default` when the host left the port unconfigured.
local function _make_port(name, default)
  return function(...)
    local fn = _resolve_port(name)
    if type(fn) ~= "function" then
      return default
    end
    return fn(...)
  end
end

function runtime_ports.configure(ports)
  configured = ports or nil
end

function runtime_ports.rng_next_int(min, max)
  local fn = _resolve_port("rng_next_int")
  assert(type(fn) == "function", "missing runtime port: rng_next_int")
  return fn(min, max)
end

function runtime_ports.schedule(delay, fn)
  local scheduler = _resolve_port("schedule")
  if type(scheduler) ~= "function" then
    if fn then
      fn()
    end
    return
  end
  return scheduler(delay, fn)
end

runtime_ports.resolve_role = _make_port("resolve_role", nil)

local _empty_roles = {}

runtime_ports.resolve_roles = _make_port("resolve_roles", _empty_roles)

runtime_ports.mark_role_lose = _make_port("mark_role_lose", nil)

-- 合成 AI 身份查询(#611):由合成角色注册表按开局登记的 player_id 回答,退役
-- (die/lose 把 actor 从注册表删除)后仍为 true。未配置端口时按「无合成 AI」
-- 处理,返回 false。
runtime_ports.is_synthetic_player = _make_port("is_synthetic_player", false)

runtime_ports.call_role_die = _make_port("call_role_die", false)

runtime_ports.resolve_camera_helper = _make_port("resolve_camera_helper", nil)

runtime_ports.emit_event = _make_port("emit_event", false)

runtime_ports.end_game = _make_port("end_game", false)

runtime_ports.wall_now_seconds = _make_port("wall_now_seconds", 0)

function runtime_ports.wall_now_hms()
  local fn = _resolve_port("wall_now_hms")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, hms = pcall(fn)
  if not ok or type(hms) ~= "string" or hms == "" then
    return nil
  end
  return hms
end

runtime_ports.wall_diff_seconds = _make_port("wall_diff_seconds", 0)

runtime_ports.cpu_now_seconds = _make_port("cpu_now_seconds", 0)

runtime_ports.cpu_diff_seconds = _make_port("cpu_diff_seconds", 0)

runtime_ports.is_effect_idle = _make_port("is_effect_idle", true)

runtime_ports.archives_enabled = _make_port("archives_enabled", false)

runtime_ports.get_archive_int = _make_port("get_archive_int", 0)

runtime_ports.set_archive_int = _make_port("set_archive_int", false)

-- #198 / ADR 0075:Str 存档(礼包码兑换记录)。读不到返回 nil,与「从未写过」
-- 的空串区分;未配置端口按读不到处理。
runtime_ports.get_archive_str = _make_port("get_archive_str", nil)

runtime_ports.set_archive_str = _make_port("set_archive_str", false)

function runtime_ports.reset_for_tests()
  configured = nil
end

-- 车道守卫用:共享测试基线(shared_support / env_runtime 加载时建立)要求本端口
-- 处于已配置态;spec teardown 拆到未配置态后不装回会泄漏给同进程后续 suite(#217)。
function runtime_ports.is_configured()
  return configured ~= nil
end

return runtime_ports

