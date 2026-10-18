local runtime_ports = require("src.foundation.ports.runtime_ports")

local event_log = {}
local DEFAULT_CAPACITY = 200

function event_log.new(capacity)
  return {
    entries = {},
    capacity = capacity or DEFAULT_CAPACITY,
    seq = 0,
    active_buffers = {},
  }
end

local function _wall_now_hms()
  local hms = runtime_ports.wall_now_hms()
  if type(hms) == "string" and hms ~= "" then
    return hms
  end
  return nil
end

local function _os_lib()
  return _G and _G.os
end

local function _date_text_ok(ok, text)
  return ok == true and type(text) == "string"
end

local function _os_date_hms()
  local os_lib = _os_lib()
  if os_lib and type(os_lib.date) == "function" then
    local ok, text = pcall(os_lib.date, "%H:%M:%S")
    if _date_text_ok(ok, text) then
      return text
    end
  end
  return nil
end

local function _now_hms()
  return _wall_now_hms() or _os_date_hms() or ""
end

local function _make_item(log, entry)
  log.seq = log.seq + 1
  return {
    kind = entry.kind,
    text = entry.text,
    seq = log.seq,
    time_text = _now_hms(),
  }
end

local function _append_with_limit(log, item)
  table.insert(log.entries, item)
  while #log.entries > log.capacity do
    table.remove(log.entries, 1)
  end
end

local function _direct_append(log, entry)
  local item = _make_item(log, entry)
  _append_with_limit(log, item)
  return item
end

function event_log.append(log, entry)
  local item = _direct_append(log, entry)
  local top = log.active_buffers[#log.active_buffers]
  if top then
    top.pending = top.pending or {}
    top.pending[#top.pending + 1] = item
  end
  return item
end

function event_log.push_buffer(log, hold)
  hold.pending = hold.pending or {}
  hold._event_log_ref = log
  log.active_buffers[#log.active_buffers + 1] = hold
end

function event_log.pop_buffer(hold)
  local log = hold and hold._event_log_ref
  if not log then
    return
  end
  for i = #log.active_buffers, 1, -1 do
    if log.active_buffers[i] == hold then
      table.remove(log.active_buffers, i)
      break
    end
  end
  hold._event_log_ref = nil
end

function event_log.flush_buffer(hold)
  if hold then
    hold.pending = nil
  end
  event_log.pop_buffer(hold)
end

function event_log.get_entries(log, limit)
  local out = {}
  local n = #log.entries
  local read_limit = limit or n
  local start = math.max(1, n - read_limit + 1)
  for i = start, n do
    out[#out + 1] = log.entries[i]
  end
  return out
end

function event_log.get_text(log, limit)
  local entries = event_log.get_entries(log, limit)
  local lines = {}
  for i, e in ipairs(entries) do
    if e.time_text then
      lines[i] = e.time_text .. " " .. e.text
    else
      lines[i] = e.text
    end
  end
  return table.concat(lines, "\n")
end

function event_log.get_seq(log)
  return log.seq
end

function event_log.clear(log)
  log.entries = {}
  log.seq = 0
  log.active_buffers = {}
end

return event_log

