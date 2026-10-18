local tip_queue = require("src.foundation.tips")

local _stringify_parts = {}

local function _stringify(...)
  local count = select("#", ...)
  for i = 1, count do
    _stringify_parts[i] = tostring(select(i, ...))
  end
  for i = count + 1, #_stringify_parts do
    _stringify_parts[i] = nil
  end
  return table.concat(_stringify_parts, " ")
end

-- 无时间前缀即不带前缀,也不留前导空格(契约)。宿主可换 time_formatter,返回空串
-- 或 nil 都算「没有前缀」。level / text 由唯一生产者 _create_entry 保证非 nil。
local function _format_entry(entry)
  local time_text = entry.time_text or ""
  if time_text ~= "" then
    return time_text .. " [" .. entry.level .. "] " .. entry.text
  end
  return "[" .. entry.level .. "] " .. entry.text
end

local function _unlimited(opts)
  return opts ~= nil and opts.unlimited == true
end

local function _has_info_limit(state)
  local limit = state.info_per_turn_limit
  local provider = state.info_turn_provider
  return limit ~= nil and limit > 0 and provider ~= nil
end

local function _reset_on_turn_change(state, turn)
  if state.info_turn ~= turn then
    state.info_turn = turn
    state.info_turn_count = 0
  end
end

local function _check_info_turn_limit(state, opts)
  if _unlimited(opts) then
    return false
  end
  if not _has_info_limit(state) then
    return false
  end
  local turn = state.info_turn_provider()
  if turn == nil then
    return false
  end
  _reset_on_turn_change(state, turn)
  if state.info_turn_count >= state.info_per_turn_limit then
    return true
  end
  state.info_turn_count = state.info_turn_count + 1
  return false
end

local function _create_entry(state, level, text, ui)
  local timestamp = state.timestamp_provider()
  local time_text = state.time_formatter(timestamp)
  return {
    level = level,
    text = text,
    ui = ui,
    timestamp = timestamp,
    time_text = time_text,
  }
end

local logger = {
  info_per_turn_limit = nil,
  info_turn_provider = nil,
  info_turn = nil,
  info_turn_count = 0,
  timestamp_provider = function()
    return 0
  end,
  time_formatter = function(timestamp)
    return tostring(timestamp)
  end,
  anim_debug_enabled_provider = nil,
  test_mode = false,
}

local function _set_timestamp_provider(provider)
  logger.timestamp_provider = provider
end

-- 时间前缀的渲染由宿主决定:formatter 返回空串即不带前缀(见 _format_entry)。
-- 这是公开接缝——调用方不该直接改 logger.time_formatter 字段。
function logger.set_time_formatter(formatter)
  assert(type(formatter) == "function", "time formatter must be function")
  logger.time_formatter = formatter
end

local _set_time_formatter = logger.set_time_formatter

function logger.reset_time_runtime()
  _set_timestamp_provider(function()
    return 0
  end)
  _set_time_formatter(function(timestamp)
    return tostring(timestamp)
  end)
end

function logger.set_anim_debug_enabled_provider(provider)
  if provider ~= nil then
    assert(type(provider) == "function", "anim debug provider must be function or nil")
  end
  logger.anim_debug_enabled_provider = provider
end

function logger.set_test_mode(enabled)
  logger.test_mode = enabled == true
  tip_queue.configure_runtime({
    test_mode = logger.test_mode,
  })
end

function logger.is_test_mode()
  return logger.test_mode == true
end

function logger.is_anim_debug_enabled()
  local provider = logger.anim_debug_enabled_provider
  if type(provider) ~= "function" then
    return false
  end
  local ok, result = pcall(provider)
  if not ok then
    return false
  end
  return result == true
end

function logger.configure_game_time(game_api)
  assert(game_api ~= nil, "missing game api")
  _set_timestamp_provider(function()
    return game_api.get_timestamp()
  end)

  local function _pad2(value)
    if value < 10 then
      return "0" .. tostring(value)
    end
    return tostring(value)
  end

  _set_time_formatter(function(timestamp)
    assert(timestamp ~= nil, "missing timestamp")
    local hour = game_api.get_hour(timestamp)
    local minute = game_api.get_minute(timestamp)
    local second = game_api.get_second(timestamp)
    return _pad2(hour) .. ":" .. _pad2(minute) .. ":" .. _pad2(second)
  end)
end

-- 每回合限流的计数只对「当前 limit + provider」这套配置有意义：换配置（新开
-- 一局会重新绑定 provider）必须作废旧账本，否则上一局用尽的配额会误伤新一局
-- 同回合号的首批 info。清掉 info_turn 就够了——下次检查发现回合号与之不符，
-- 会顺手把计数归零（见 _check_info_turn_limit）。
local function _reset_info_turn_accounting()
  logger.info_turn = nil
end

function logger.set_info_per_turn_limit(limit)
  logger.info_per_turn_limit = limit
  _reset_info_turn_accounting()
end

function logger.set_info_turn_provider(provider)
  logger.info_turn_provider = provider
  _reset_info_turn_accounting()
end

function logger.set_ui_sink(sink)
  logger.ui_sink = sink
end

-- entry.ui 是唯一上屏凭证(#522):仅 opts.ui == true 时置 true,其余保持 nil,
-- 让 sink 的「entry.ui == true 才上屏」判定与调用点显式声明一一对应。
local function _ui_flag(opts)
  if opts ~= nil and opts.ui == true then
    return true
  end
  return nil
end

local function _push(state, level, opts, ...)
  if level == "info" and _check_info_turn_limit(state, opts) then
    return
  end
  local text = _stringify(...)
  local entry = _create_entry(state, level, text, _ui_flag(opts))
  if state.ui_sink then
    state.ui_sink(entry)
  end
  if type(print) == "function" then
    pcall(print, _format_entry(entry))
  end
end

local function _level_logger(level)
  return function(...)
    _push(logger, level, nil, ...)
  end
end

logger.info = _level_logger("info")
logger.warn = _level_logger("warn")

local _warn_ui_opts = { ui = true }

-- #522:warn 默认只进 log.txt(print),ui_sink 不再无条件上屏——116 个 warn
-- 调用点逐条盘点均为开发者留痕,玩家可见的规则提示走 tip_queue 专用通道。
-- 确需上屏的 warn 用 warn_ui 显式声明;上屏白名单 = 全部 warn_ui 调用点
-- (grep 可得,2026-08-20 盘点时为空)。
function logger.warn_ui(...)
  _push(logger, "warn", _warn_ui_opts, ...)
end

local _info_unlimited_opts = { unlimited = true }

function logger.info_unlimited(...)
  _push(logger, "info", _info_unlimited_opts, ...)
end

function logger.log_once(sink, level, key, ...)
  assert(type(sink) == "table", "missing dedupe sink")
  if sink[key] then
    return false
  end
  sink[key] = true
  if level == "warn" then
    logger.warn(...)
  else
    logger.info(...)
  end
  return true
end

return logger

