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

