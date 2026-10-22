-- 档案读写默认实现(自 default_ports.lua 拆分,行为保持):经 defaults.resolve_role
-- 解析角色(调用时解析,须在 role_ports.install 之后安装)。Int 读失败统一回落 0,
-- 写失败返回 false;Str(#198 / ADR 0075 礼包码兑换记录)读失败返回 nil——与
-- 「从未写过」的空串区分,调用方据此拒绝而不是覆盖已有记录——写失败返回 false,
-- 每条降级路径留 warn。宿主写档无成功返回值约定,是否落档由调用方写后回读判定。
-- 宿主签名无 self(真机取证 2026-08-26:带 self 报 params count mismatch,
-- get 期望 2 参 (archive_type, key),set 期望 3 参 (archive_type, key, value),
-- 与 EggyAPI.lua 注解一致),故按普通函数直调,不用冒号约定。
local number_utils = require("src.foundation.number")
local logger = require("src.foundation.log")

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

local function _str_archive_type()
  return Enums and Enums.ArchiveType and Enums.ArchiveType.Str or nil
end

local function _warn_str(action, reason, role_id, key)
  logger.warn(
    "archive_ports: str archive " .. action .. " skipped",
    "reason=" .. tostring(reason),
    "role_id=" .. tostring(role_id),
    "key=" .. tostring(key)
  )
end

-- 返回 (role, archive_type, nil) 或 (nil, nil, 跳过原因)。
local function _str_target(defaults, role_id, method)
  local archive_type = _str_archive_type()
  if archive_type == nil then
    return nil, nil, "missing_str_archive_type"
  end
  local role = defaults.resolve_role(role_id)
  if role == nil then
    return nil, nil, "missing_role"
  end
  if type(role[method]) ~= "function" then
    return nil, nil, "missing_" .. method
  end
  return role, archive_type, nil
end

local function _read_archive_str(defaults, role_id, key)
  local role, archive_type, reason = _str_target(defaults, role_id, "get_archive_by_type")
  if reason ~= nil then
    _warn_str("read", reason, role_id, key)
    return nil
  end
  local ok, value = pcall(role.get_archive_by_type, archive_type, key)
  if not ok then
    _warn_str("read", value, role_id, key)
    return nil
  end
  if type(value) ~= "string" then
    _warn_str("read", "non_string_value:" .. type(value), role_id, key)
    return nil
  end
  return value
end

local function _write_archive_str(defaults, role_id, key, value)
  local role, archive_type, reason = _str_target(defaults, role_id, "set_archive_by_type")
  if reason ~= nil then
    _warn_str("write", reason, role_id, key)
    return false
  end
  local ok, err = pcall(role.set_archive_by_type, archive_type, key, value)
  if not ok then
    _warn_str("write", err, role_id, key)
    return false
  end
  return true
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

  defaults.get_archive_str = function(role_id, key)
    return _read_archive_str(defaults, role_id, key)
  end

  defaults.set_archive_str = function(role_id, key, value)
    return _write_archive_str(defaults, role_id, key, value)
  end
end

return archive_ports

