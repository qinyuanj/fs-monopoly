local number_utils = require("src.foundation.number")
local runtime_state = require("src.state.runtime")
local entries = require("src.turn.deadlines.entries")

local service = {}

local function _ensure_active(state)
  local deadlines = runtime_state.ensure_deadlines(state)
  return deadlines.active
end

function service.start(state, scope, opts)
  assert(type(state) == "table", "missing state")
  assert(type(scope) == "string" and scope ~= "", "invalid scope")
  opts = opts or {}
  local timeout = entries.resolve_timeout(opts)
  if timeout <= 0 then
    return nil
  end
  local active = _ensure_active(state)
  active[scope] = entries.new_entry(scope, opts, timeout)
  return active[scope]
end

function service.cancel(state, scope)
  if type(state) ~= "table" or type(scope) ~= "string" then
    return false
  end
  local active = _ensure_active(state)
  if active[scope] == nil then
    return false
  end
  active[scope] = nil
  return true
end

local function _entry_outranks(entry, primary)
  return primary == nil or (entry.priority or 0) > (primary.priority or 0)
end

local function _primary_entry(active)
  local primary = nil
  for _, entry in pairs(active) do
    if _entry_outranks(entry, primary) then
      primary = entry
    end
  end
  return primary
end

local function _peek_entry(entry)
  return entry and entries.build_peek_result(entry) or nil
end

function service.peek(state, scope)
  if type(state) ~= "table" then
    return nil
  end
  local active = _ensure_active(state)
  if scope == "primary" then
    return _peek_entry(_primary_entry(active))
  end
  return _peek_entry(active[scope])
end

local _expired_scopes = {}
local _expired_entries = {}

function service.tick(state, dt)
  if type(state) ~= "table" then
    return
  end
  if not number_utils.is_numeric(dt) or dt <= 0 then
    return
  end
  local active = _ensure_active(state)
  local expired_n = 0
  for scope, entry in pairs(active) do
    expired_n = entries.collect_expired_entry(scope, entry, dt, expired_n, _expired_scopes, _expired_entries)
  end
  entries.expire_collected_entries(active, expired_n, _expired_scopes, _expired_entries)
end

function service.is_active(state, scope)
  if type(state) ~= "table" or type(scope) ~= "string" then
    return false
  end
  local active = _ensure_active(state)
  return active[scope] ~= nil
end

return service

