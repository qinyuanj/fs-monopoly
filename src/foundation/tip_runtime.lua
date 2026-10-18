local number_utils = require("src.foundation.number")
local tip_util = require("src.foundation.tip_util")

local tip_runtime = {}

local function _try_set_runtime_field(runtime, adapter, field, target_key, error_msg, reset_fn)
  local fn = adapter[field]
  if fn == nil then return end
  assert(type(fn) == "function", error_msg)
  runtime[target_key] = fn
  if reset_fn then reset_fn() end
end

local function _apply_numeric_fields(runtime, adapter)
  if number_utils.is_numeric(adapter.event_tip_fast_backlog_threshold) then
    runtime.event_tip_fast_backlog_threshold = adapter.event_tip_fast_backlog_threshold
  end
  if number_utils.is_numeric(adapter.event_tip_fast_seconds) then
    runtime.event_tip_fast_seconds = adapter.event_tip_fast_seconds
  end
end

-- dispatch_next_tip 由 tips 显式传入（队列调度回调）；presenter 缺失告警的
-- warned 标记住在 tip_queue.runtime.presenter_warned，换上新 presenter 时在此复位。
function tip_runtime.configure(tip_queue_ref, adapter, dispatch_next_tip)
  adapter = adapter or {}
  local runtime = tip_queue_ref.runtime

  local function _try_set_presenter_field(adap, field)
    _try_set_runtime_field(runtime, adap, field, "presenter",
      "tip presenter must be function or nil",
      function() runtime.presenter_warned = false end)
  end

  local function _try_set_scheduler_field(adap, field)
    _try_set_runtime_field(runtime, adap, field, "scheduler",
      "tip scheduler must be function or nil")
  end

  if adapter.clear_presenter == true then
    runtime.presenter = nil
  end
  _try_set_presenter_field(adapter, "presenter")
  if adapter.clear_scheduler == true then
    runtime.scheduler = nil
  end
  _try_set_scheduler_field(adapter, "scheduler")

  if adapter.test_mode ~= nil then
    runtime.test_mode = adapter.test_mode == true
  end
  _apply_numeric_fields(runtime, adapter)

  tip_util.each_scope(tip_queue_ref, dispatch_next_tip)
end

return tip_runtime

--[[ mutate4lua-manifest
version=4
projectHash=353db19b36e8358c
scope.0.id=chunk:src/foundation/tip_runtime.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=61
scope.0.semanticHash=6e13110ba13f4462
scope.1.id=function:_try_set_runtime_field
scope.1.kind=function
scope.1.startLine=6
scope.1.endLine=12
scope.1.semanticHash=b93b146edacf2ff0
scope.2.id=function:_apply_numeric_fields
scope.2.kind=function
scope.2.startLine=14
scope.2.endLine=21
scope.2.semanticHash=f5671f19d148d602
scope.3.id=function:tip_runtime.configure
scope.3.kind=function
scope.3.startLine=25
scope.3.endLine=58
scope.3.semanticHash=8eca1141b24b7d06
scope.4.id=function:_try_set_presenter_field
scope.4.kind=function
scope.4.startLine=29
scope.4.endLine=33
scope.4.semanticHash=2f5aa38ebcde4054
scope.5.id=function:<anonymous>
scope.5.kind=function
scope.5.startLine=32
scope.5.endLine=32
scope.5.semanticHash=a46115e13b2d6b86
scope.6.id=function:_try_set_scheduler_field
scope.6.kind=function
scope.6.startLine=35
scope.6.endLine=38
scope.6.semanticHash=c3543736719f42b5
]]
