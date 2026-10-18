require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local tip_queue = require("src.foundation.tips")

local _config_reset = require("test.support.config_reset")

local function _assert_eq(a, b, msg)
  luassert.is.equal(b, a, msg)
end

local function _reset()
  tip_queue.clear()
  tip_queue.configure_runtime({
    clear_presenter = true,
    clear_scheduler = true,
    test_mode = false,
    event_tip_fast_backlog_threshold = 2,
    event_tip_fast_seconds = 0.5,
  })
end

describe("TestTipQueue", function()

  before_each(function()
    _config_reset.reset_all()
  end)

  after_each(function()
    -- 清了共享 tips 基线必须装回,否则 mutate 车道窄 suite 子集撞空 presenter(#217)
    support.restore_runtime_services()
  end)

  it("test_enqueue 携带 role_id 交给 presenter：私人提示只投给该玩家", function()
    _reset()
    local seen
    tip_queue.configure_runtime({
      presenter = function(_, _, tip) seen = tip end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "私人", duration = 2.0, role_id = 7 })
    _assert_eq(seen and seen.role_id, 7, "role_id should reach the presenter")
    _reset()
  end)

  it("test_不带 role_id 的提示保持广播语义(role_id 为 nil)", function()
    _reset()
    local seen
    tip_queue.configure_runtime({
      presenter = function(_, _, tip) seen = tip end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "全场", duration = 2.0 })
    _assert_eq(seen and seen.text, "全场", "tip should be presented")
    _assert_eq(seen and seen.role_id, nil, "broadcast tips must not invent a role")
    _reset()
  end)

  -- 队列按「投给谁」分区串行:两块屏幕上的提示不该互相排队。分区前全场共用一条
  -- 队列,甲的 2 秒提示会把乙的提示压住,主观就是「点了没反应」。
  it("test_不同 role 的私人提示各自独立排队,互不阻塞", function()
    _reset()
    local shown = {}
    tip_queue.configure_runtime({
      presenter = function(text) shown[#shown + 1] = text end,
      scheduler = function() return true end,  -- 认领但不回调:提示停在 active 态
    })
    tip_queue.enqueue({ text = "甲的提示", duration = 2.0, role_id = 1 })
    tip_queue.enqueue({ text = "乙的提示", duration = 2.0, role_id = 2 })
    _assert_eq(#shown, 2, "a held tip on one screen must not stall another screen")
    _assert_eq(shown[2], "乙的提示", "the second role's tip should present immediately")
    _reset()
  end)

  it("test_同一 role 的提示仍然串行,不会两条同屏叠着", function()
    _reset()
    local shown = {}
    tip_queue.configure_runtime({
      presenter = function(text) shown[#shown + 1] = text end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "第一条", duration = 2.0, role_id = 1 })
    tip_queue.enqueue({ text = "第二条", duration = 2.0, role_id = 1 })
    _assert_eq(#shown, 1, "same-screen tips stay serialized")
    _reset()
  end)

  it("test_私人提示不占用全局队列,广播提示照常先出", function()
    _reset()
    local shown = {}
    tip_queue.configure_runtime({
      presenter = function(text) shown[#shown + 1] = text end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "私人", duration = 2.0, role_id = 1 })
    tip_queue.enqueue({ text = "全场", duration = 2.0 })
    _assert_eq(#shown, 2, "broadcast tips must not queue behind a private one")
    _reset()
  end)

  it("test_inter_turn 阻塞闸跨全部 scope", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "阻塞", duration = 2.0, role_id = 3, blocks_inter_turn = true })
    luassert.truthy(tip_queue.has_blocking_pending("inter_turn") == true, "a blocking tip on any screen must hold inter_turn")
    tip_queue.clear()
    luassert.truthy(tip_queue.has_blocking_pending("inter_turn") == false, "clear must drop every scope")
    _reset()
  end)

  it("test_configure_runtime clear_presenter", function()
    _reset()
    tip_queue.configure_runtime({ presenter = function() end })
    tip_queue.configure_runtime({ clear_presenter = true })
    _assert_eq(tip_queue.runtime.presenter, nil, "clear_presenter should remove presenter")
    _reset()
  end)

  -- 调度三分支的释放语义(批次4 提取 _immediate_release/_wrapped_release/
  -- _invoked_ok/_handled_ok 后,这三条分支没有测试直接驱动):
  -- 无调度器立即释放 / 调度器同步回调只释放一次 / 调度器不认领时回退立即释放。
  it("test_enqueue 无调度器时立即释放且只释放一次", function()
    _reset()
    local calls = 0
    tip_queue.configure_runtime({
      presenter = function() calls = calls + 1 end,
      clear_scheduler = true,
    })
    luassert.truthy(tip_queue.enqueue({ text = "无调度器", duration = 2.0 }) == true, "enqueue should accept the tip without a scheduler")
    _assert_eq(calls, 1, "without a scheduler the tip should be presented exactly once")
  end)

  it("test_scheduler 同步回调时经回调释放且不重复", function()
    _reset()
    local calls = 0
    tip_queue.configure_runtime({
      presenter = function() calls = calls + 1 end,
      scheduler = function(_, fn)
        fn()
        return true
      end,
      -- test_mode 打开:同步回调路径若误判为「未 invoked」会走 test-mode 重复释放,
      -- 断言恰好一次才能钉住 _invoked_ok 的 invoked 查询。
      test_mode = true,
    })
    tip_queue.enqueue({ text = "同步回调", duration = 2.0 })
    _assert_eq(calls, 1, "sync-invoking scheduler should release once through the callback")
  end)

  it("test_scheduler 不认领时回退立即释放", function()
    _reset()
    local calls = 0
    tip_queue.configure_runtime({
      presenter = function() calls = calls + 1 end,
      scheduler = function() end,
    })
    tip_queue.enqueue({ text = "不认领", duration = 2.0 })
    _assert_eq(calls, 1, "scheduler returning nothing should fall back to immediate release")
  end)

  it("test_configure_runtime clear_scheduler", function()
    _reset()
    tip_queue.configure_runtime({ scheduler = function() end })
    tip_queue.configure_runtime({ clear_scheduler = true })
    _assert_eq(tip_queue.runtime.scheduler, nil, "clear_scheduler should remove scheduler")
    _reset()
  end)

  it("test_configure_runtime invalid presenter asserts", function()
    _reset()
    local ok, err = pcall(function()
      tip_queue.configure_runtime({ presenter = "not_a_function" })
    end)
    _assert_eq(ok, false, "non-function presenter should assert")
    luassert.truthy(tostring(err):find("function", 1, true), "error should mention function: " .. tostring(err))
    _reset()
  end)

  it("test_configure_runtime invalid scheduler asserts", function()
    _reset()
    local ok, err = pcall(function()
      tip_queue.configure_runtime({ scheduler = 42 })
    end)
    _assert_eq(ok, false, "non-function scheduler should assert")
    luassert.truthy(tostring(err):find("tip scheduler must be function or nil", 1, true) ~= nil, "scheduler assert should carry its message: " .. tostring(err))
    _reset()
  end)

  it("test_presenter_warned_resets_when_a_new_presenter_arrives", function()
    -- #293:tip_runtime 换上新 presenter 时复位 presenter_warned(false→true 变异
    -- 会让复位失效,第二次缺 presenter 不再告警)。warn 走 logger→print,
    -- 用 log_capture 数告警次数。
    local log_capture = require("test.support.log_capture")
    _reset()
    local _, _, first = log_capture.capture(function()
      tip_queue.enqueue({ text = "缺 presenter", duration = 2.0 })
    end)
    local first_warns = 0
    for _, line in ipairs(first.lines) do
      if line:find("presenter not registered", 1, true) then first_warns = first_warns + 1 end
    end
    _assert_eq(first_warns, 1, "first missing-presenter enqueue should warn once")

    tip_queue.configure_runtime({ presenter = function() end })
    tip_queue.configure_runtime({ clear_presenter = true })
    local _, _, second = log_capture.capture(function()
      tip_queue.enqueue({ text = "又缺 presenter", duration = 2.0 })
    end)
    local second_warns = 0
    for _, line in ipairs(second.lines) do
      if line:find("presenter not registered", 1, true) then second_warns = second_warns + 1 end
    end
    _assert_eq(second_warns, 1, "fresh presenter must reset the warned flag so the warning fires again")
    _reset()
  end)

  it("test_normalize_duration_accepts_fractional_positive", function()
    -- #293:tip_util.normalize_duration 的 `> 0` 边界(`0`→`1` 变异)未测。
    local tip_util = require("src.foundation.tip_util")
    _assert_eq(tip_util.normalize_duration(0.5), 0.5,
      "fractional positive durations should pass through")
    _assert_eq(tip_util.normalize_duration(0), 2.0, "zero should fall back to the default")
  end)

  it("test_release_tip advances to next pending", function()
    _reset()
    local release_cb = nil
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function(_, fn)
        release_cb = fn
        return true
      end,
    })
    tip_queue.enqueue({ text = "first", duration = 1.0 })
    tip_queue.enqueue({ text = "second", duration = 1.0 })
    luassert.truthy(tip_queue.active_tip ~= nil, "first tip should be active")
    luassert.truthy(#tip_queue.pending == 1, "second tip should be in pending")
    release_cb()
    luassert.truthy(tip_queue.active_tip ~= nil, "second tip should become active after release")
    luassert.truthy(tip_queue.active_tip.text == "second", "second tip should be dispatched")
    _reset()
  end)

  it("test_enqueue nil text returns false", function()
    _reset()
    local ok = tip_queue.enqueue({ text = nil, duration = 1.0 })
    _assert_eq(ok, false, "nil text should return false")
    _reset()
  end)

  it("test_enqueue dedup by active_tip", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function() return true end,
    })
    local ok1 = tip_queue.enqueue({ text = "msg", duration = 1.0, dedupe_key = "k1" })
    _assert_eq(ok1, true, "first enqueue should succeed")
    luassert.truthy(tip_queue.active_tip ~= nil, "tip should remain active with deferring scheduler")
    local ok2 = tip_queue.enqueue({ text = "msg2", duration = 1.0, dedupe_key = "k1" })
    _assert_eq(ok2, false, "duplicate key matching active_tip should return false")
    _reset()
  end)

  it("test_enqueue dedup by pending", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function()
        return true
      end,
    })
    tip_queue.enqueue({ text = "tip1", duration = 1.0 })
    local ok = tip_queue.enqueue({ text = "tip2", duration = 1.0, dedupe_key = "pending_k" })
    _assert_eq(ok, true, "different key should be enqueued")
    local ok2 = tip_queue.enqueue({ text = "tip3", duration = 1.0, dedupe_key = "pending_k" })
    _assert_eq(ok2, false, "same key in pending should be deduped")
    _reset()
  end)

  it("test_has_blocking_pending non-inter_turn returns false", function()
    _reset()
    tip_queue.enqueue({ text = "msg", duration = 1.0, blocks_inter_turn = true })
    _assert_eq(tip_queue.has_blocking_pending("move"), false,
      "non-inter_turn phase should return false regardless")
    _reset()
  end)

  it("test_has_blocking_pending no blocking tip returns false", function()
    _reset()
    tip_queue.enqueue({ text = "msg", duration = 1.0, blocks_inter_turn = false })
    _assert_eq(tip_queue.has_blocking_pending("inter_turn"), false,
      "non-blocking tip should return false")
    _reset()
  end)

  it("test_has_blocking_pending blocking active_tip returns true", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "msg", duration = 1.0, blocks_inter_turn = true })
    luassert.truthy(tip_queue.active_tip ~= nil, "tip should be active with deferring scheduler")
    _assert_eq(tip_queue.has_blocking_pending("inter_turn"), true,
      "blocking active_tip should return true")
    _reset()
  end)

  it("test_has_blocking_pending blocking tip in pending", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function()
        return true
      end,
    })
    tip_queue.enqueue({ text = "first", duration = 1.0 })
    tip_queue.enqueue({ text = "blocking", duration = 1.0, blocks_inter_turn = true })
    _assert_eq(tip_queue.has_blocking_pending("inter_turn"), true,
      "blocking tip in pending should return true")
    _reset()
  end)

  it("test_schedule_release no scheduler calls release immediately", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
    })
    tip_queue.enqueue({ text = "tip", duration = 0.5 })
    _assert_eq(tip_queue.active_tip, nil,
      "without scheduler, tip should be released immediately (active_tip cleared)")
    _reset()
  end)

  it("test_schedule_release scheduler invokes callback directly", function()
    _reset()
    local scheduler_called = false
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function(_, fn)
        scheduler_called = true
        fn()
      end,
    })
    tip_queue.enqueue({ text = "tip", duration = 0.5 })
    _assert_eq(scheduler_called, true, "scheduler should be called")
    _assert_eq(tip_queue.active_tip, nil, "tip released when scheduler invokes callback")
    _reset()
  end)

  it("test_schedule_release scheduler defers with test_mode releases tip", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function()
        return true
      end,
      test_mode = true,
    })
    tip_queue.enqueue({ text = "tip", duration = 0.5 })
    _assert_eq(tip_queue.active_tip, nil,
      "in test_mode, returning true from scheduler should still release tip")
    _reset()
  end)

  it("test_schedule_release scheduler defers no test_mode keeps tip", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function()
        return true
      end,
      test_mode = false,
    })
    tip_queue.enqueue({ text = "tip", duration = 0.5 })
    luassert.truthy(tip_queue.active_tip ~= nil, "without test_mode, returning true from scheduler should keep tip active")
    _reset()
  end)

  it("test_snapshot reflects empty queue state", function()
    _reset()
    local s = tip_queue.snapshot()
    _assert_eq(s.has_presenter, false, "no presenter configured")
    _assert_eq(s.has_scheduler, false, "no scheduler configured")
    _assert_eq(s.pending_count, 0, "no pending tips")
    _assert_eq(s.active_text, nil, "no active tip")
    _assert_eq(type(s.epoch), "number", "epoch is a number")
    _assert_eq(s.test_mode, false, "test_mode defaults false")
    _reset()
  end)

  it("test_snapshot reflects configured presenter and active tip", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "hello", duration = 1.0 })
    tip_queue.enqueue({ text = "world", duration = 1.0 })
    local s = tip_queue.snapshot()
    _assert_eq(s.has_presenter, true, "presenter is set")
    _assert_eq(s.has_scheduler, true, "scheduler is set")
    _assert_eq(s.active_text, "hello", "active tip text")
    _assert_eq(s.pending_count, 1, "one tip in pending")
    _reset()
  end)

  it("test_clear increments epoch by exactly 1 to invalidate stale releases", function()
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "tip", duration = 1.0 })
    local epoch_before = tip_queue.epoch
    tip_queue.clear()
    local epoch_after = tip_queue.epoch
    _assert_eq(epoch_after - epoch_before, 1, "clear must increment epoch by exactly 1")
    _reset()
  end)

  it("test_normalize_duration defaults to 2.0 for zero duration", function()
    _reset()
    local shown = {}
    tip_queue.configure_runtime({
      presenter = function(text, duration)
        shown[#shown + 1] = { text = text, duration = duration }
      end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "zero_dur", duration = 0 })
    _assert_eq(#shown, 1, "tip with zero duration should still be presented")
    _assert_eq(shown[1].duration, 2.0, "zero duration should default to 2.0")
    _reset()
  end)

  it("test_normalize_duration defaults to 2.0 for negative duration", function()
    _reset()
    local shown = {}
    tip_queue.configure_runtime({
      presenter = function(text, duration)
        shown[#shown + 1] = { text = text, duration = duration }
      end,
      scheduler = function() return true end,
    })
    tip_queue.enqueue({ text = "neg_dur", duration = -3.0 })
    _assert_eq(#shown, 1, "tip with negative duration should still be presented")
    _assert_eq(shown[1].duration, 2.0, "negative duration should default to 2.0")
    _reset()
  end)

  it("test_backlog_acceleration uses fast_seconds when backlog reaches threshold", function()
    _reset()
    local timers = {}
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function(delay, fn)
        timers[#timers + 1] = { delay = delay, fn = fn }
        return true
      end,
      event_tip_fast_backlog_threshold = 1,
      event_tip_fast_seconds = 0.5,
    })
    tip_queue.enqueue({ text = "a", duration = 5.0 })
    tip_queue.enqueue({ text = "b", duration = 5.0 })
    tip_queue.enqueue({ text = "c", duration = 5.0 })
    _assert_eq(#timers, 1, "only first tip should be scheduled (others pending)")
    timers[1].fn()
    _assert_eq(#timers, 2, "second tip scheduled after first releases")
    _assert_eq(timers[2].delay, 0.5, "backlog at threshold should apply fast_seconds")
    _reset()
  end)

  it("test_backlog_acceleration preserves duration when backlog below threshold", function()
    _reset()
    local timers = {}
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function(delay, fn)
        timers[#timers + 1] = { delay = delay, fn = fn }
        return true
      end,
      event_tip_fast_backlog_threshold = 2,
      event_tip_fast_seconds = 0.5,
    })
    tip_queue.enqueue({ text = "a", duration = 5.0 })
    tip_queue.enqueue({ text = "b", duration = 5.0 })
    tip_queue.enqueue({ text = "c", duration = 5.0 })
    timers[1].fn()
    _assert_eq(timers[2].delay, 5.0, "backlog below threshold should preserve duration")
    _reset()
  end)

  it("test_backlog_acceleration preserves duration when fast_seconds exceeds duration", function()
    _reset()
    local timers = {}
    tip_queue.configure_runtime({
      presenter = function() end,
      scheduler = function(delay, fn)
        timers[#timers + 1] = { delay = delay, fn = fn }
        return true
      end,
      event_tip_fast_backlog_threshold = 1,
      event_tip_fast_seconds = 10.0,
    })
    tip_queue.enqueue({ text = "a", duration = 3.0 })
    tip_queue.enqueue({ text = "b", duration = 3.0 })
    timers[1].fn()
    _assert_eq(timers[2].delay, 3.0, "fast_seconds > duration should preserve shorter duration")
    _reset()
  end)

  it("test_schedule_release calls release_fn exactly once when scheduler invokes synchronously", function()
    _reset()
    local presented = {}
    tip_queue.configure_runtime({
      presenter = function(text)
        presented[#presented + 1] = text
      end,
      scheduler = function(_, fn)
        fn()
      end,
    })
    tip_queue.enqueue({ text = "sync1", duration = 1.0 })
    tip_queue.enqueue({ text = "sync2", duration = 1.0 })
    _assert_eq(#presented, 2, "both tips should be presented")
    _assert_eq(presented[1], "sync1", "first tip presented")
    _assert_eq(presented[2], "sync2", "second tip presented")
    _assert_eq(tip_queue.active_tip, nil, "queue drained after synchronous release")
    _reset()
  end)

  it("test_apply_numeric_runtime_field ignores non-numeric values", function()
    _reset()
    tip_queue.configure_runtime({
      event_tip_fast_backlog_threshold = "not_a_number",
      event_tip_fast_seconds = nil,
    })
    _assert_eq(tip_queue.runtime.event_tip_fast_backlog_threshold, 2,
      "non-numeric threshold should not update runtime field")
    _assert_eq(tip_queue.runtime.event_tip_fast_seconds, 0.5,
      "nil seconds should not update runtime field")
    _reset()
  end)

  it("test_apply_numeric_runtime_field accepts numeric values", function()
    _reset()
    tip_queue.configure_runtime({
      event_tip_fast_backlog_threshold = 5,
      event_tip_fast_seconds = 1.5,
    })
    _assert_eq(tip_queue.runtime.event_tip_fast_backlog_threshold, 5,
      "numeric threshold should update runtime field")
    _assert_eq(tip_queue.runtime.event_tip_fast_seconds, 1.5,
      "numeric seconds should update runtime field")
    _reset()
  end)

  it("test_present_tip handles presenter error and continues queue", function()
    _reset()
    local call_count = 0
    local timers = {}
    tip_queue.configure_runtime({
      presenter = function()
        call_count = call_count + 1
        if call_count == 1 then
          error("presenter boom")
        end
      end,
      scheduler = function(delay, fn)
        timers[#timers + 1] = { delay = delay, fn = fn }
        return true
      end,
    })
    tip_queue.enqueue({ text = "fail", duration = 1.0 })
    tip_queue.enqueue({ text = "recover", duration = 1.0 })
    _assert_eq(call_count, 1, "first tip should be presented (and error)")
    timers[1].fn()
    _assert_eq(call_count, 2, "second tip should be presented after first releases")
    _reset()
  end)

  it("test_presenter_warned_prevents_repeated_warnings_within_same_runtime_session", function()
    -- kills L92 true -> false: presenter_warned 设 true 后同 session 内不重复告警.
    local log_capture = require("test.support.log_capture")
    _reset()
    local _, _, captured = log_capture.capture(function()
      tip_queue.enqueue({ text = "first", duration = 2.0 })
      tip_queue.enqueue({ text = "second", duration = 2.0 })
    end)
    local warn_count = 0
    for _, line in ipairs(captured.lines) do
      if line:find("[tip_queue]", 1, true) then warn_count = warn_count + 1 end
    end
    _assert_eq(warn_count, 1, "only one warn for the first missing-presenter enqueue, not both")
    _reset()
  end)

  it("test_present_tip_handles_presenter_error_and_logs_to_warn", function()
    -- kills L93 [tip_queue] -> nil, L98 not -> removed not, L99 string/tostring -> nil.
    local log_capture = require("test.support.log_capture")
    _reset()
    tip_queue.configure_runtime({
      presenter = function() error("BOOM_12345") end,
      scheduler = function(_, fn) fn() end,
    })
    local _, _, captured = log_capture.capture(function()
      tip_queue.enqueue({ text = "will_error", duration = 1.0 })
    end)
    local warn_lines = {}
    for _, line in ipairs(captured.lines) do
      if line:find("[tip_queue]", 1, true) then
        warn_lines[#warn_lines + 1] = line
      end
    end
    _assert_eq(#warn_lines, 1, "presenter error should trigger exactly one warn with [tip_queue] prefix")
    luassert.truthy(warn_lines[1]:find("presenter raised error", 1, true) ~= nil, "warn should carry presenter raised error caption")
    luassert.truthy(warn_lines[1]:find("BOOM_12345", 1, true) ~= nil, "warn should include the original error message")
    luassert.truthy(warn_lines[1]:find("will_error", 1, true) ~= nil, "warn should include the tip text that caused the error")
    _reset()
  end)

  it("test_no_scheduler_drains_multiple_tips_without_double_presenting", function()
    -- kills L108 true -> false: no-scheduler 时 _immediate_release 返回 true 走 early return.
    _reset()
    tip_queue.configure_runtime({
      presenter = function() end,
    })
    tip_queue.enqueue({ text = "a", duration = 1.0 })
    tip_queue.enqueue({ text = "b", duration = 1.0 })
    tip_queue.enqueue({ text = "c", duration = 1.0 })
    _assert_eq(tip_queue.active_tip, nil, "without scheduler all tips should drain")
    _assert_eq(#tip_queue.pending, 0, "pending queue should be empty after drain")
    _reset()
  end)


end)
