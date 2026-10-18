local tip_util = require("src.foundation.tip_util")
local tip_runtime = require("src.foundation.tip_runtime")

local function _warn(...)
  local ok, log = pcall(require, "src.foundation.log")
  if ok and type(log) == "table" and type(log.warn) == "function" then
    log.warn(...)
  end
end

-- 队列按「投给谁」分区串行:不带 role_id 的提示(事件流等)住全局 scope,行为与
-- 分区前完全一致;带 role_id 的私人提示(如道具槽拒绝)各自独立排队。
-- 分区前所有人共用一条串行队列,甲的 2 秒提示会把乙屏幕上的提示一起压住,
-- 主观就是「点了没反应」——而两人根本不在同一块屏幕上,本就不该互相排队。
-- 全局 scope 的字段直接挂在 tip_queue 上(pending / active_tip),既有读者不变。
local tip_queue = {
  pending = {},
  active_tip = nil,
  role_scopes = {},
  runtime = {
    presenter = nil,
    scheduler = nil,
    test_mode = false,
    event_tip_fast_backlog_threshold = 2,
    event_tip_fast_seconds = 0.5,
  },
  epoch = 0,
}

local function _backlog_threshold()
  return tip_queue.runtime.event_tip_fast_backlog_threshold or 2
end

local function _fast_seconds()
  return tip_queue.runtime.event_tip_fast_seconds or 0.5
end

local function _scope(role_id)
  return tip_util.resolve_scope(tip_queue, role_id)
end

local function _each_scope(fn)
  return tip_util.each_scope(tip_queue, fn)
end

local function _apply_backlog_acceleration(scope, duration)
  local backlog = #scope.pending
  if backlog < _backlog_threshold() then
    return duration
  end
  local fast = _fast_seconds()
  if fast < duration then
    return fast
  end
  return duration
end

local function _normalize_duration(duration)
  return tip_util.normalize_duration(duration)
end

local function _normalize_intent(intent)
  return tip_util.normalize_intent(intent, _normalize_duration)
end

local function _pending_has_key(pending, dedupe_key)
  for i = 1, #pending do
    if pending[i].dedupe_key == dedupe_key then
      return true
    end
  end
  return false
end

local function _has_matching_dedupe_key(scope, dedupe_key)
  if dedupe_key == nil then
    return false
  end
  local active_tip = scope.active_tip
  if active_tip ~= nil and active_tip.dedupe_key == dedupe_key then
    return true
  end
  return _pending_has_key(scope.pending, dedupe_key)
end

local function _present_tip(tip)
  local presenter = tip_queue.runtime.presenter
  if type(presenter) ~= "function" then
    -- warned 标记住 runtime 表（tip_runtime 在换上新 presenter 时负责复位），
    -- 避免模块级 local 经 ref 在 configure 间 round-trip。
    if not tip_queue.runtime.presenter_warned then
      tip_queue.runtime.presenter_warned = true
      _warn("[tip_queue]", "presenter not registered - tips will be dropped until configure_runtime is called")
    end
    return false
  end
  local ok, err = pcall(presenter, tip.text, tip.duration, tip)
  if not ok then
    _warn("[tip_queue]", "presenter raised error:", tostring(err), "| text:", tostring(tip.text))
  end
  return ok
end

local function _immediate_release(scheduler, release_fn)
  if type(scheduler) ~= "function" then
    release_fn()
    return true
  end
  return false
end

-- 包装 release_fn 并暴露「是否已被调用」的查询,调度回调与原语义一致。
local function _wrapped_release(release_fn)
  local invoked = false
  return function()
    return invoked
  end, function()
    invoked = true
    release_fn()
  end
end

local function _invoked_ok(ok, is_invoked)
  return ok ~= nil and is_invoked()
end

local function _handled_ok(ok, handled)
  return ok ~= nil and handled == true
end

local function _test_mode_release(release_fn)
  if tip_queue.runtime.test_mode == true then
    release_fn()
  end
end

local function _schedule_release(delay, release_fn)
  local scheduler = tip_queue.runtime.scheduler
  if _immediate_release(scheduler, release_fn) then
    return
  end

  local is_invoked, _wrapped = _wrapped_release(release_fn)
  local ok, handled = pcall(scheduler, delay, _wrapped)
  if _invoked_ok(ok, is_invoked) then
    return
  end
  if _handled_ok(ok, handled) then
    _test_mode_release(release_fn)
    return
  end
  release_fn()
end

local function _effective_duration(scope, tip)
  return _apply_backlog_acceleration(scope, tip.duration)
end

local _activate_next_pending

local function _release_tip(epoch, scope, tip)
  if tip_queue.epoch ~= epoch then
    return
  end
  if scope.active_tip ~= tip then
    return
  end
  scope.active_tip = nil
  _activate_next_pending(scope)
end

function _activate_next_pending(scope)
  local pending = scope.pending
  if #pending <= 0 then
    return
  end
  local next_tip = table.remove(pending, 1)
  scope.active_tip = next_tip
  local current_epoch = tip_queue.epoch
  _present_tip(next_tip)
  _schedule_release(_effective_duration(scope, next_tip), function()
    _release_tip(current_epoch, scope, next_tip)
  end)
end

local function _dispatch_next_tip(scope)
  if scope.active_tip ~= nil then
    return
  end
  _activate_next_pending(scope)
end

function tip_queue.configure_runtime(adapter)
  -- 私有的 _dispatch_next_tip 作显式参数传给 tip_runtime，不挂公开表
  -- （挂在 tip_queue 上任何持有者可覆盖，会静默破坏队列调度）。
  tip_runtime.configure(tip_queue, adapter, _dispatch_next_tip)
end

function tip_queue.enqueue(intent)
  local tip = _normalize_intent(intent)
  if tip == nil then
    return false
  end
  local scope = _scope(tip.role_id)
  if _has_matching_dedupe_key(scope, tip.dedupe_key) then
    return false
  end
  local pending = scope.pending
  pending[#pending + 1] = tip
  _dispatch_next_tip(scope)
  return true
end

-- inter_turn 闸跨全部 scope:任何一块屏幕上还压着阻塞提示,回合就不该翻页。
function tip_queue.has_blocking_pending(phase_name)
  if phase_name ~= "inter_turn" then
    return false
  end
  return _each_scope(function(scope)
    local active_tip = scope.active_tip
    if active_tip ~= nil and active_tip.blocks_inter_turn == true then
      return true
    end
    local pending = scope.pending
    for i = 1, #pending do
      if pending[i].blocks_inter_turn == true then
        return true
      end
    end
    return nil
  end) == true
end

function tip_queue.clear()
  tip_queue.pending = {}
  tip_queue.active_tip = nil
  tip_queue.role_scopes = {}
  tip_queue.epoch = tip_queue.epoch + 1
end

local function _pending_count()
  local total = 0
  _each_scope(function(scope)
    total = total + #scope.pending
    return nil
  end)
  return total
end

function tip_queue.snapshot()
  return {
    has_presenter = type(tip_queue.runtime.presenter) == "function",
    has_scheduler = type(tip_queue.runtime.scheduler) == "function",
    pending_count = _pending_count(),
    active_text = tip_queue.active_tip and tip_queue.active_tip.text or nil,
    epoch = tip_queue.epoch,
    test_mode = tip_queue.runtime.test_mode,
  }
end

return tip_queue

