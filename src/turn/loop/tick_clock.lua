local number_utils = require("src.foundation.number")
local runtime_constants = require("src.config.gameplay.runtime_constants")

local tick_clock = {}

local function _resolve_fallback_tick_seconds(interval)
  local fps = runtime_constants.fps
  if not number_utils.is_numeric(fps) or fps <= 0 then
    fps = 30.0
  end
  return math.tofixed(interval) / fps
end

local function _normalize_positive_dt(value)
  if not number_utils.is_numeric(value) or value <= 0 then
    return nil
  end
  if value > 1.0 then
    return 1.0
  end
  return value
end

local function _is_integer_like_time(value)
  if not number_utils.is_numeric(value) then
    return false
  end
  local as_int = number_utils.to_integer(value)
  if as_int == nil then
    return false
  end
  return value == as_int
end

local function _resolve_clock_from_state(state)
  if not state then
    return nil
  end
  local ports = state.gameplay_loop_ports
  return ports and ports.clock or nil
end

local function _resolve_wall_functions(clock)
  if not clock then
    return nil, nil
  end
  return clock.wall_now_seconds, clock.wall_diff_seconds
end

local function _try_get_now(wall_now_seconds)
  if type(wall_now_seconds) ~= "function" then
    return nil, false
  end
  local ok_now, now = pcall(wall_now_seconds)
  if not ok_now or not number_utils.is_numeric(now) then
    return nil, false
  end
  return now, true
end

local function _update_tick_state(state, now)
  local previous = state.tick_wall_now_seconds
  state.tick_wall_now_seconds = now
  return previous
end

local function _try_wall_diff(wall_diff_seconds, a, b)
  if type(wall_diff_seconds) ~= "function" then
    return nil, false
  end
  local ok_diff, diff = pcall(wall_diff_seconds, a, b)
  local normalized = _normalize_positive_dt(diff)
  if ok_diff and normalized ~= nil then
    return normalized, true, diff
  end
  return nil, false, diff
end

local function _try_raw_diff(a, b)
  local raw_diff = a - b
  local normalized = _normalize_positive_dt(raw_diff)
  if normalized ~= nil then
    return normalized, true, raw_diff
  end
  return nil, false, raw_diff
end

local function _try_resolve_wall_diff(wall_diff_seconds, now, previous)
  local diff_result, diff_ok, diff_raw = _try_wall_diff(wall_diff_seconds, now, previous)
  if diff_ok then
    return diff_result, "wall:diff", diff_raw
  end
  local reverse_result, reverse_ok, reverse_raw = _try_wall_diff(wall_diff_seconds, previous, now)
  if reverse_ok then
    return reverse_result, "wall:diff_reversed", reverse_raw
  end
  return nil, nil, diff_raw
end

local function _try_resolve_raw_diff(now, previous)
  local raw_result, raw_ok, raw_val = _try_raw_diff(now, previous)
  if raw_ok then
    return raw_result, "wall:raw_diff", raw_val
  end
  local raw_rev_result, raw_rev_ok, raw_rev_val = _try_raw_diff(previous, now)
  if raw_rev_ok then
    return raw_rev_result, "wall:raw_diff_reversed", raw_rev_val
  end
  return nil, nil, nil
end

local function _resolve_tick_fallback(state, fallback_seconds, reason)
  return fallback_seconds, reason, state and state.tick_wall_now_seconds or nil, nil, nil
end

local function _try_resolve_tick_diff(wall_diff_seconds, now, previous, fallback_seconds)
  if _is_integer_like_time(now) and _is_integer_like_time(previous) then
    return fallback_seconds, "fallback:coarse_wall_clock", now, previous, nil
  end

  local wall_result, wall_tag, wall_raw = _try_resolve_wall_diff(wall_diff_seconds, now, previous)
  if wall_result ~= nil then
    return wall_result, wall_tag, now, previous, wall_raw
  end

  local raw_result, raw_tag, raw_val = _try_resolve_raw_diff(now, previous)
  if raw_result ~= nil then
    return raw_result, raw_tag, now, previous, raw_val
  end

  return fallback_seconds, "fallback:diff_invalid", now, previous, wall_raw
end

local function _try_get_previous_tick(state, now)
  local previous = _update_tick_state(state, now)
  if not number_utils.is_numeric(previous) then
    return nil, "fallback:no_previous"
  end
  return previous, nil
end

tick_clock.resolve_fallback_tick_seconds = _resolve_fallback_tick_seconds

-- state 上时钟的 wall 函数对;缺任一返回 nil(调用方走 no_clock 兜底)。
local function _clock_wall_functions(state)
  local clock = _resolve_clock_from_state(state)
  local wall_now_seconds, wall_diff_seconds = _resolve_wall_functions(clock)
  if not wall_now_seconds or not wall_diff_seconds then
    return nil
  end
  return wall_now_seconds, wall_diff_seconds
end

function tick_clock.resolve_tick_seconds(state, fallback_seconds)
  if not state then
    return _resolve_tick_fallback(nil, fallback_seconds, "fallback:no_state")
  end

  local wall_now_seconds, wall_diff_seconds = _clock_wall_functions(state)
  if not wall_now_seconds then
    return _resolve_tick_fallback(state, fallback_seconds, "fallback:no_clock")
  end

  local now, ok_now = _try_get_now(wall_now_seconds)
  if not ok_now then
    return _resolve_tick_fallback(state, fallback_seconds, "fallback:now_invalid")
  end

  local previous, previous_err = _try_get_previous_tick(state, now)
  if previous_err then
    return fallback_seconds, previous_err, now, nil, nil
  end

  return _try_resolve_tick_diff(wall_diff_seconds, now, previous, fallback_seconds)
end

return tick_clock

