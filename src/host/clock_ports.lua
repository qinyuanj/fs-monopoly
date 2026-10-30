-- 时钟端口默认实现(自 default_ports.lua 拆分,行为保持):wall/cpu 时刻与差值
-- 的宿主 API 适配,经 runtime_context 取当前 env 的 GameAPI 时间戳方法。
local number_utils = require("src.foundation.number")
local host_context = require("src.host.context")

local clock_ports = {}

local function _try_timestamp_from_api(game_api)
  if game_api and type(game_api.get_timestamp) == "function" then
    local ok, ts = pcall(game_api.get_timestamp)
    if ok and number_utils.is_numeric(ts) then
      return ts
    end
  end
  return nil
end

local function _api_now_seconds(runtime_context)
  local ts = _try_timestamp_from_api(host_context.current_api(runtime_context, "Game" .. "API"))
  return ts or 0
end

local function _part_fn(game_api, fn_name)
  local fn = game_api[fn_name]
  if type(fn) ~= "function" then
    return nil
  end
  return fn
end

local function _numeric_part(fn, ts_value)
  local ok, val = pcall(fn, ts_value)
  if not ok or not number_utils.is_numeric(val) then
    return nil
  end
  return number_utils.to_integer(val)
end

local function _safe_part(game_api, fn_name, ts)
  local fn = _part_fn(game_api, fn_name)
  if fn == nil then
    return nil
  end
  return _numeric_part(fn, ts)
end

local function _parts_complete(h, m, s)
  return h ~= nil and m ~= nil and s ~= nil
end

local function _wall_now_hms(runtime_context)
  local game_api = host_context.current_api(runtime_context, "Game" .. "API")
  if game_api == nil then
    return ""
  end
  local ts = _try_timestamp_from_api(game_api)
  if ts == nil then
    return ""
  end
  local h = _safe_part(game_api, "get_hour", ts)
  local m = _safe_part(game_api, "get_minute", ts)
  local s = _safe_part(game_api, "get_second", ts)
  if not _parts_complete(h, m, s) then
    return ""
  end
  return string.format("%02d:%02d:%02d", h, m, s)
end

local function _diff_ready(game_api, t1, t2)
  return game_api ~= nil and type(game_api.get_timestamp_diff) == "function"
    and number_utils.is_numeric(t1) and number_utils.is_numeric(t2)
end

local function _safe_timestamp_diff(game_api, t1, t2)
  local ok, diff = pcall(game_api.get_timestamp_diff, t1, t2)
  if ok and number_utils.is_numeric(diff) then
    return diff
  end
  return nil
end

local function _timestamp_diff(game_api, t1, t2)
  if _diff_ready(game_api, t1, t2) then
    return _safe_timestamp_diff(game_api, t1, t2)
  end
  return nil
end

function clock_ports.install(defaults, runtime_context)
  defaults.wall_now_seconds = function()
    return _api_now_seconds(runtime_context)
  end

  defaults.wall_now_hms = function()
    return _wall_now_hms(runtime_context)
  end

  defaults.wall_diff_seconds = function(timestamp_1, timestamp_2)
    return _timestamp_diff(host_context.current_api(runtime_context, "Game" .. "API"), timestamp_1, timestamp_2)
      or number_utils.diff_or_zero(timestamp_1, timestamp_2)
  end

  defaults.cpu_now_seconds = function()
    return _api_now_seconds(runtime_context)
  end

  defaults.cpu_diff_seconds = number_utils.diff_or_zero
end

return clock_ports

