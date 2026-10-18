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

