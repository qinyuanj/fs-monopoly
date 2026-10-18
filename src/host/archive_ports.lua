-- int 档案读写默认实现(自 default_ports.lua 拆分,行为保持):经 defaults.resolve_role
-- 解析角色(调用时解析,须在 role_ports.install 之后安装),读失败统一回落 0,
-- 写失败返回 false。
-- 宿主签名无 self(真机取证 2026-08-26:带 self 报 params count mismatch,
-- get 期望 2 参 (archive_type, key),set 期望 3 参 (archive_type, key, value),
-- 与 EggyAPI.lua 注解一致),故按普通函数直调,不用冒号约定。
local number_utils = require("src.foundation.number")

local archive_ports = {}

local function _current_env(runtime_context)
  local ctx = runtime_context.current and runtime_context.current() or nil
  return ctx and ctx.env or nil
end

local function _current_game_api(runtime_context)
  local env = _current_env(runtime_context)
  return env and env["Game" .. "API"] or nil
end

local function _int_archive_type()
  return Enums and Enums.ArchiveType and Enums.ArchiveType.Int or nil
end

function archive_ports.archives_enabled(runtime_context)
  local game_api = _current_game_api(runtime_context)
  if game_api and type(game_api.is_archives_enabled) == "function" then
    local ok, enabled = pcall(game_api.is_archives_enabled)
    if ok then
      return enabled == true
    end
  end
  return false
end

local function _has_archive_reader(role, archive_type)
  return role and archive_type ~= nil and type(role.get_archive_by_type) == "function"
end

local function _read_archive_int(role, archive_type, key)
  if not _has_archive_reader(role, archive_type) then
    return 0
  end
  local ok, value = pcall(role.get_archive_by_type, archive_type, key)
  if ok and number_utils.is_numeric(value) then
    return value
  end
  return 0
end

function archive_ports.install(defaults, runtime_context)
  defaults.archives_enabled = function()
    return archive_ports.archives_enabled(runtime_context)
  end

  defaults.get_archive_int = function(role_id, key)
    local role = defaults.resolve_role(role_id)
    local archive_type = _int_archive_type()
    return _read_archive_int(role, archive_type, key)
  end

  defaults.set_archive_int = function(role_id, key, value)
    local role = defaults.resolve_role(role_id)
    local archive_type = _int_archive_type()
    if not (role and archive_type ~= nil and type(role.set_archive_by_type) == "function") then
      return false
    end
    local ok = pcall(role.set_archive_by_type, archive_type, key, value)
    return ok == true
  end
end

return archive_ports

