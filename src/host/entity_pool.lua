local unit_lifecycle = require("src.host.units")
local number_utils = require("src.foundation.number")
local logger = require("src.foundation.log")
local runtime_constants = require("src.config.gameplay.runtime_constants")

local entity_pool = {}

local _buckets = {}
local _max_idle = runtime_constants.entity_pool_max_idle

local function _bucket(unit_key)
  if not _buckets[unit_key] then
    _buckets[unit_key] = { idle = {}, live = 0, peak = 0, miss = 0 }
  end
  return _buckets[unit_key]
end

local function _access_field(obj, key)
  return obj[key]
end

local function _call_method(handle, name, ...)
  if handle == nil then return end
  local _, method = pcall(_access_field, handle, name)
  pcall(method, ...)
end

function entity_pool.acquire(unit_key, pos, rotation, scale)
  -- ADR 0046「跳过必留痕」:nil 入参静默跳过是 #339 清障机器人盲区之一。
  if unit_key == nil then
    logger.warn("[entity_pool]", "acquire with nil unit_key")
    return nil
  end
  if pos == nil then
    logger.warn("[entity_pool]", "acquire with nil pos for key=" .. tostring(unit_key))
    return nil
  end
  local b = _bucket(unit_key)
  local handle
  if #b.idle > 0 then
    handle = table.remove(b.idle)
    _call_method(handle, "set_position", pos)
    _call_method(handle, "set_orientation", rotation)
    _call_method(handle, "set_world_scale", scale)
    _call_method(handle, "set_model_visible", true)
  else
    b.miss = b.miss + 1
    handle = unit_lifecycle.create_unit_with_scale(unit_key, pos, rotation, scale)
    if handle == nil then
      logger.warn("[entity_pool]", "create_unit_with_scale returned nil for key=" .. tostring(unit_key))
      return nil
    end
  end
  b.live = b.live + 1
  b.peak = math.max(b.peak, b.live)
  return handle
end

local function _return_or_destroy(b, handle)
  if #b.idle < _max_idle then
    b.idle[#b.idle + 1] = handle
  else
    unit_lifecycle.destroy_unit(handle)
  end
end

function entity_pool.release(unit_key, handle)
  if unit_key == nil or handle == nil then return end
  local b = _bucket(unit_key)
  _call_method(handle, "set_model_visible", false)
  _call_method(handle, "set_position", runtime_constants.entity_pool_park_pos)
  _return_or_destroy(b, handle)
  if number_utils.is_numeric(b.live) and b.live > 0 then
    b.live = b.live - 1
  end
end

local function _valid_prewarm_args(unit_key, count)
  return unit_key ~= nil and number_utils.is_numeric(count) and count > 0
end

local function _prewarm_one(unit_key, b, pos, rotation, scale)
  local handle = unit_lifecycle.create_unit_with_scale(unit_key, pos, rotation, scale)
  if not handle then return end
  _call_method(handle, "set_model_visible", false)
  _call_method(handle, "set_position", runtime_constants.entity_pool_park_pos)
  b.idle[#b.idle + 1] = handle
end

local function _fill_prewarm(unit_key, b, count, pos, rotation, scale)
  for _ = 1, count - #b.idle do
    if #b.idle >= _max_idle then break end
    _prewarm_one(unit_key, b, pos, rotation, scale)
  end
end

function entity_pool.prewarm(unit_key, count, rotation, scale, sample_pos)
  if not _valid_prewarm_args(unit_key, count) then return end
  local b = _bucket(unit_key)
  _fill_prewarm(unit_key, b, count, sample_pos or runtime_constants.entity_pool_park_pos, rotation, scale)
end

function entity_pool.stats()
  local snapshot = {}
  for unit_key, b in pairs(_buckets) do
    snapshot[unit_key] = {
      idle = #b.idle,
      live = b.live,
      peak = b.peak,
      miss = b.miss,
    }
  end
  return snapshot
end

function entity_pool.reset()
  for _, b in pairs(_buckets) do
    for _, handle in ipairs(b.idle) do
      unit_lifecycle.destroy_unit(handle)
    end
    b.idle = {}
  end
end

return entity_pool

