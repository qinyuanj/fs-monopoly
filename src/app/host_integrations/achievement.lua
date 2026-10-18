local number_utils = require("src.foundation.number")
local catalog = require("src.config.content.achievements")
local event_progress = require("src.config.content.achievement_progress_events")
local role_resolver = require("src.host.role_resolver")

local achievement = {}

local progress_adapter = nil

local function _copy_ids(ids)
  local copy = {}
  for index, id in ipairs(ids or {}) do
    copy[index] = id
  end
  return copy
end

local function _resolve_adapter(role)
  if role ~= nil then
    return role
  end
  if progress_adapter ~= nil then
    return progress_adapter
  end
  local roles = role_resolver.resolve_roles()
  return roles and roles[1] or nil
end

local function _valid_progress_args(id, amount)
  return achievement.find(id) ~= nil and number_utils.to_integer(amount) ~= nil
end

local function _call_host(adapter, method_name, ...)
  if adapter == nil or type(adapter[method_name]) ~= "function" then
    return nil
  end
  local ok, result = pcall(adapter[method_name], ...)
  if not ok or result == false then
    return false
  end
  return true, result
end

local function _apply_progress(id, amount, method_name, role)
  local achievement_id = number_utils.to_integer(id)
  local progress_count = number_utils.to_integer(amount)
  if not _valid_progress_args(achievement_id, progress_count) then
    return false
  end
  local ok = _call_host(_resolve_adapter(role), method_name, achievement_id, progress_count)
  return ok == true
end

-- 行为测试公共查询：test_achievement 按编辑器 ID 观察成就目录；生产进度校验共用此查询。
function achievement.find(id)
  local target_id = number_utils.to_integer(id)
  if target_id == nil then
    return nil
  end

  for _, entry in ipairs(catalog) do
    if entry.id == target_id then
      return entry
    end
  end
  return nil
end

-- 行为测试的宿主边界注入/复位接缝：验证事件分发、进度增量与宿主拒绝，不伪造游戏内部状态。
function achievement.configure_progress_adapter(adapter)
  progress_adapter = adapter
end

function achievement.reset_for_tests()
  progress_adapter = nil
end

-- 行为测试公共查询：属性场景据此观察事件映射与扇出，并验证返回载荷不能污染映射。
function achievement.mapped_ids_for_event(event_name)
  local mapped = event_progress[event_name]
  if mapped == nil then
    return {}
  end
  return _copy_ids(mapped.ids)
end

function achievement.add_progress(id, amount, role)
  return _apply_progress(id, amount, "add_achievement_progress", role)
end

-- 行为测试公共查询：经宿主读取进度，观察 record_gameplay_event 的累计增量。
function achievement.current_progress(id, role)
  local achievement_id = number_utils.to_integer(id)
  if achievement.find(achievement_id) == nil then
    return nil
  end
  local ok, result = _call_host(_resolve_adapter(role), "get_achievement_progress", achievement_id)
  if ok ~= true then
    return nil
  end
  return number_utils.to_integer(result)
end

function achievement.record_gameplay_event(event_name, event_value, role)
  local mapped = event_progress[event_name]
  if mapped == nil then
    return false
  end

  local amount = number_utils.to_integer(event_value)
  if amount == nil then
    amount = mapped.default_amount
  end
  local advanced = false
  for _, id in ipairs(mapped.ids) do
    if achievement.add_progress(id, amount, role) then
      advanced = true
    end
  end
  return advanced
end

return achievement

--[[ mutate4lua-manifest
version=4
projectHash=f523577bf59b1929
scope.0.id=chunk:src/app/host_integrations/achievement.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=186
scope.0.semanticHash=85f021233f96ab53
scope.1.id=function:_copy_ids
scope.1.kind=function
scope.1.startLine=13
scope.1.endLine=19
scope.1.semanticHash=4e7b6f91220a0270
scope.2.id=function:_resolve_adapter
scope.2.kind=function
scope.2.startLine=21
scope.2.endLine=30
scope.2.semanticHash=1252d14ff5387d9e
scope.3.id=function:_valid_progress_args
scope.3.kind=function
scope.3.startLine=32
scope.3.endLine=34
scope.3.semanticHash=4e4a65341d925213
scope.4.id=function:_call_host
scope.4.kind=function
scope.4.startLine=36
scope.4.endLine=45
scope.4.semanticHash=305f61440bce8e34
scope.5.id=function:_apply_progress
scope.5.kind=function
scope.5.startLine=47
scope.5.endLine=55
scope.5.semanticHash=af118d6e6fd9b158
scope.6.id=function:_id_range
scope.6.kind=function
scope.6.startLine=57
scope.6.endLine=64
scope.6.semanticHash=ae861b1ecfa4f3eb
scope.7.id=function:_has_every_id
scope.7.kind=function
scope.7.startLine=66
scope.7.endLine=73
scope.7.semanticHash=a0f57e4e3fce77d9
scope.8.id=function:achievement.list
scope.8.kind=function
scope.8.startLine=75
scope.8.endLine=77
scope.8.semanticHash=1136505bd37c301e
scope.9.id=function:achievement.count
scope.9.kind=function
scope.9.startLine=79
scope.9.endLine=81
scope.9.semanticHash=740726d371eb97be
scope.10.id=function:achievement.find
scope.10.kind=function
scope.10.startLine=83
scope.10.endLine=95
scope.10.semanticHash=91d37655756b1d1c
scope.11.id=function:achievement.category_counts
scope.11.kind=function
scope.11.startLine=97
scope.11.endLine=104
scope.11.semanticHash=c59eac78b41be414
scope.12.id=function:achievement.ids_are_contiguous
scope.12.kind=function
scope.12.startLine=106
scope.12.endLine=117
scope.12.semanticHash=e964e0c48131a058
scope.13.id=function:achievement.configure_progress_adapter
scope.13.kind=function
scope.13.startLine=119
scope.13.endLine=121
scope.13.semanticHash=139af97e09c42e84
scope.14.id=function:achievement.reset_for_tests
scope.14.kind=function
scope.14.startLine=123
scope.14.endLine=125
scope.14.semanticHash=f308d8708726be18
scope.15.id=function:achievement.mapped_ids_for_event
scope.15.kind=function
scope.15.startLine=127
scope.15.endLine=133
scope.15.semanticHash=62507cea6a32f51b
scope.16.id=function:achievement.add_progress
scope.16.kind=function
scope.16.startLine=135
scope.16.endLine=137
scope.16.semanticHash=d0f66380fffb2f3d
scope.17.id=function:achievement.current_progress
scope.17.kind=function
scope.17.startLine=139
scope.17.endLine=149
scope.17.semanticHash=6d5b191b29acb7ea
scope.18.id=function:achievement.set_progress
scope.18.kind=function
scope.18.startLine=151
scope.18.endLine=153
scope.18.semanticHash=d0f66380fffb2f3d
scope.19.id=function:achievement.record_gameplay_event
scope.19.kind=function
scope.19.startLine=155
scope.19.endLine=172
scope.19.semanticHash=590fc35caba6e256
scope.20.id=function:achievement.snapshot
scope.20.kind=function
scope.20.startLine=174
scope.20.endLine=183
scope.20.semanticHash=d5fc2809bf66be5e
]]
