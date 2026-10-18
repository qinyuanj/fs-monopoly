local number_utils = require("src.foundation.number")
local timing = require("src.config.gameplay.timing")
local logger = require("src.foundation.log")

local entries = {}

local _default_thresholds = { 5, 3 }
local _peek_result = {}

local function _resolve_thresholds()
  local cfg = timing.deadline_warning_thresholds
  if type(cfg) ~= "table" then
    return _default_thresholds
  end
  return cfg
end

function entries.resolve_timeout(opts)
  if not opts then
    return 0
  end
  if number_utils.is_numeric(opts.timeout_seconds) and opts.timeout_seconds > 0 then
    return opts.timeout_seconds
  end
  return 0
end

function entries.new_entry(scope, opts, timeout)
  return {
    scope = scope,
    elapsed = 0,
    timeout = timeout,
    on_timeout = opts.on_timeout,
    on_warn = opts.on_warn,
    priority = number_utils.is_numeric(opts.priority) and opts.priority or 0,
    fired_warn_5s = false,
    fired_warn_3s = false,
    fired_timeout = false,
    started_at = nil,
  }
end

local function _call_deadline_callback(callback, label, warn_args, ...)
  if type(callback) ~= "function" then
    return
  end
  local ok, err = pcall(callback, ...)
  if not ok then
    logger.warn("[Eggy]", label, table.unpack(warn_args), tostring(err))
  end
end

local function _fire_warn(entry, level)
  _call_deadline_callback(entry.on_warn, "DeadlineService.on_warn error", { entry.scope, level }, level)
end

local function _warn_thresholds(thresholds)
  return thresholds[1] or 5, thresholds[2] or 3
end

local function _should_fire_warn_5s(entry, remaining, warn_5s, warn_3s)
  return not entry.fired_warn_5s and remaining <= warn_5s and remaining > warn_3s
end

local function _should_fire_warn_3s(entry, remaining, warn_3s)
  return not entry.fired_warn_3s and remaining <= warn_3s and remaining > 0
end

local function _maybe_fire_warns(entry, remaining, thresholds)
  local warn_5s, warn_3s = _warn_thresholds(thresholds)
  if _should_fire_warn_5s(entry, remaining, warn_5s, warn_3s) then
    entry.fired_warn_5s = true
    _fire_warn(entry, "warn_5s")
  end
  if _should_fire_warn_3s(entry, remaining, warn_3s) then
    entry.fired_warn_3s = true
    _fire_warn(entry, "warn_3s")
  end
end

local function _active_level_from_remaining(remaining, thresholds)
  local warn_3s = thresholds[2] or 3
  local warn_5s = thresholds[1] or 5
  if remaining <= warn_3s then
    return "warn_3s"
  end
  if remaining <= warn_5s then
    return "warn_5s"
  end
  return "normal"
end

local function _level_from_remaining(remaining, thresholds)
  if remaining <= 0 then
    return "expired"
  end
  return _active_level_from_remaining(remaining, thresholds)
end

function entries.build_peek_result(entry)
  local remaining = entry.timeout - entry.elapsed
  if remaining < 0 then remaining = 0 end
  _peek_result.scope = entry.scope
  _peek_result.remaining_seconds = remaining
  _peek_result.elapsed_seconds = entry.elapsed
  _peek_result.timeout_seconds = entry.timeout
  _peek_result.level = _level_from_remaining(remaining, _resolve_thresholds())
  return _peek_result
end

function entries.collect_expired_entry(scope, entry, dt, expired_n, expired_scopes, expired_entries)
  if entry.fired_timeout then
    return expired_n
  end
  entry.elapsed = (entry.elapsed or 0) + dt
  local remaining = entry.timeout - entry.elapsed
  _maybe_fire_warns(entry, remaining, _resolve_thresholds())
  if entry.elapsed < entry.timeout then
    return expired_n
  end
  entry.fired_timeout = true
  expired_n = expired_n + 1
  expired_scopes[expired_n] = scope
  expired_entries[expired_n] = entry
  return expired_n
end

local function _fire_timeout(entry, scope)
  _call_deadline_callback(entry.on_timeout, "DeadlineService.on_timeout error", { scope }, scope)
end

function entries.expire_collected_entries(active, expired_n, expired_scopes, expired_entries)
  for i = 1, expired_n do
    local scope = expired_scopes[i]
    local entry = expired_entries[i]
    expired_scopes[i] = nil
    expired_entries[i] = nil
    active[scope] = nil
    _fire_timeout(entry, scope)
  end
end

return entries

