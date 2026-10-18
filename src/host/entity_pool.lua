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
  -- 返回值无读者、ok/type 守卫与 pcall 吞错殊途同归(method 不可调用时
  -- pcall 自行吞掉),一并删除(#259 化简);handle nil 守卫保留——它让
  -- `== nil` 翻转变异体能被「有效 handle 必须被调用」用例直接杀死。
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
  -- math.max 形态:原 `b.live > b.peak` 的 > -> >= 在等值时重复赋同值不可杀;
  -- live/peak 是内部不变量(恒数值),is_numeric 双守卫是死防御(#259 化简)。
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
  -- 预热失败(handle nil)跳过本格,由循环继续尝试下一格;返回值无读者,
  -- 满池早退移给 _fill_prewarm 的 break(#259 化简:`return false` -> true
  -- 在旧形态下只改变无副作用的迭代次数,不可杀)。
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

-- 行为测试公共接缝：test_entity_pool 通过快照观测复用、容量上限和 reset 的资源结果。
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

--[[ mutate4lua-manifest
version=4
projectHash=a5f2640532652d50
scope.0.id=chunk:src/host/entity_pool.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=134
scope.0.semanticHash=5808a9c19e238ccb
scope.1.id=function:_bucket
scope.1.kind=function
scope.1.startLine=11
scope.1.endLine=16
scope.1.semanticHash=f9d42cb697b3cb83
scope.2.id=function:_access_field
scope.2.kind=function
scope.2.startLine=18
scope.2.endLine=20
scope.2.semanticHash=2aa97b277475fba2
scope.3.id=function:_call_method
scope.3.kind=function
scope.3.startLine=22
scope.3.endLine=29
scope.3.semanticHash=63836312a4c480f0
scope.4.id=function:entity_pool.acquire
scope.4.kind=function
scope.4.startLine=31
scope.4.endLine=62
scope.4.semanticHash=664f38fd6a1622c9
scope.5.id=function:_return_or_destroy
scope.5.kind=function
scope.5.startLine=64
scope.5.endLine=70
scope.5.semanticHash=3646c8b1ae055bde
scope.6.id=function:entity_pool.release
scope.6.kind=function
scope.6.startLine=72
scope.6.endLine=81
scope.6.semanticHash=a247981c7e4fde3a
scope.7.id=function:_valid_prewarm_args
scope.7.kind=function
scope.7.startLine=83
scope.7.endLine=85
scope.7.semanticHash=81c86b11e0c63bec
scope.8.id=function:_prewarm_one
scope.8.kind=function
scope.8.startLine=87
scope.8.endLine=96
scope.8.semanticHash=0c11ee51b6f040fd
scope.9.id=function:_fill_prewarm
scope.9.kind=function
scope.9.startLine=98
scope.9.endLine=103
scope.9.semanticHash=052bf6952713e4ac
scope.10.id=function:entity_pool.prewarm
scope.10.kind=function
scope.10.startLine=105
scope.10.endLine=109
scope.10.semanticHash=13695051d9157e6d
scope.11.id=function:entity_pool.stats
scope.11.kind=function
scope.11.startLine=111
scope.11.endLine=122
scope.11.semanticHash=34ccfdf689097d46
scope.12.id=function:entity_pool.reset
scope.12.kind=function
scope.12.startLine=124
scope.12.endLine=131
scope.12.semanticHash=3b66acf8cf65fc5e
]]
