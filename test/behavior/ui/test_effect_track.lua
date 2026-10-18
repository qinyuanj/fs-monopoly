-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local effect_track = require("src.ui.render.support.effect_track")

local function _assert_eq(a, b, msg)
  luassert.truthy(a == b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

local function _spawn_active_tokens(count)
  for i = 1, count do
    effect_track.spawn(i, "cash_receive", 0.1, nil)
  end
end

local function _with_runtime_port_mocks(fn)
  runtime_ports.reset_for_tests()
  effect_track.reset()
  runtime_ports.configure({
    schedule = function() end,
    wall_now_seconds = function() return 0 end,
  })

  local ok, err = pcall(fn)

  runtime_ports.reset_for_tests()
  effect_track.reset()

  if not ok then
    error(err, 2)
  end
end

local function _with_schedule_capture(fn)
  runtime_ports.reset_for_tests()
  effect_track.reset()
  local scheduled = {}
  runtime_ports.configure({
    schedule = function(delay, fn_sched)
      scheduled[#scheduled + 1] = { delay = delay, fn = fn_sched }
    end,
    wall_now_seconds = function() return 0 end,
  })

  local ok, err = pcall(function()
    fn(scheduled)
  end)

  runtime_ports.reset_for_tests()
  effect_track.reset()

  if not ok then
    error(err, 2)
  end
end

describe("TestEffectTrack", function()

  after_each(function()
    support.restore_runtime_services()
  end)

  -- 活动演出等待与取消行为。

  it("test_await_all_polls_until_effects_drain_then_invokes_the_callback", function()
    local callbacks = {}
    local scheduled = {}
    runtime_ports.reset_for_tests()
    effect_track.reset()
    runtime_ports.configure({
      schedule = function(delay, fn)
        scheduled[#scheduled + 1] = { delay = delay, fn = fn }
      end,
      wall_now_seconds = function() return 0 end,
    })

    local ok, err = pcall(function()
      effect_track.spawn("cue1", "kind", 0.1)
      local idle = effect_track.await_all(function()
        callbacks[#callbacks + 1] = "done"
      end)

      _assert_eq(idle, false, "await_all should report pending effects")
      _assert_eq(#callbacks, 0, "callback should wait while effects are active")
      luassert.truthy(#scheduled >= 2, "spawn and await should schedule callbacks")

      scheduled[1].fn()
      scheduled[#scheduled].fn()
    end)

    runtime_ports.reset_for_tests()
    effect_track.reset()
    if not ok then
      error(err)
    end

    _assert_eq(callbacks[1], "done", "await callback should run after effects drain")
  end)

  it("test_cancel_nil_or_completed_returns_false", function()
    _with_runtime_port_mocks(function()
      _assert_eq(effect_track.cancel(nil), false, "nil token returns false")
      local token = effect_track.spawn(1, "cash_receive", 0.1, nil)
      token.completed = true
      _assert_eq(effect_track.cancel(token), false, "completed token returns false")
    end)
  end)

  it("test_cancel_active_token_returns_true_once", function()
    _with_runtime_port_mocks(function()
      local token = effect_track.spawn(1, "cash_receive", 0.1, nil)
      _assert_eq(effect_track.cancel(token), true, "active token cancelled")
      _assert_eq(effect_track.cancel(token), false, "second cancel returns false")
      _assert_eq(effect_track.is_idle(), true, "cancelled token should not remain active")
    end)
  end)

  -- ===== 补测：spawn 默认值与 token 字段 =====

  it("test_spawn_default_duration_is_zero", function()
    _with_runtime_port_mocks(function()
      local token = effect_track.spawn("id1", "cash_receive", nil, nil)
      _assert_eq(token.duration, 0, "nil duration should default to 0")
      _assert_eq(token.id, "id1", "token should carry id")
      _assert_eq(token.kind, "cash_receive", "token should carry kind")
    end)
  end)

  it("test_spawn_assigns_incrementing_token_ids", function()
    _with_runtime_port_mocks(function()
      local t1 = effect_track.spawn("a", "cash_receive", 0.1, nil)
      local t2 = effect_track.spawn("b", "cash_receive", 0.1, nil)
      _assert_eq(t1.token_id, 1, "first token should have id 1")
      _assert_eq(t2.token_id, 2, "second token should have id 2")
    end)
  end)

  it("test_spawn_token_has_spawned_at_field", function()
    _with_runtime_port_mocks(function()
      local token = effect_track.spawn("x", "cash_receive", 0.1, nil)
      _assert_eq(token.spawned_at, 0, "spawned_at should come from wall_now_seconds mock")
    end)
  end)

  it("test_spawn_schedules_timeout_with_effective_timeout", function()
    _with_schedule_capture(function(scheduled)
      effect_track.spawn("t1", "kind", nil, nil)
      luassert.truthy(#scheduled >= 1, "spawn should schedule timeout callback")
      local timeout_delay = scheduled[1].delay
      -- effective_timeout = (nil or 0) + 10 = 10
      _assert_eq(timeout_delay, 10.0, "nil duration should give default timeout seconds")
    end)
  end)

  it("test_spawn_with_explicit_duration_schedules_correct_timeout", function()
    _with_schedule_capture(function(scheduled)
      effect_track.spawn("t1", "kind", 5.0, nil)
      local timeout_delay = scheduled[1].delay
      _assert_eq(timeout_delay, 15.0, "explicit duration + timeout_seconds")
    end)
  end)

  it("test_reset_clears_state", function()
    _with_runtime_port_mocks(function()
      _spawn_active_tokens(3)
      _assert_eq(effect_track.is_idle(), false, "should have active tokens before reset")
      effect_track.reset()
      _assert_eq(effect_track.is_idle(), true, "reset should clear all tokens")
      -- next spawn should get token_id = 1
      local t = effect_track.spawn("new", "cash_receive", 0.1, nil)
      _assert_eq(t.token_id, 1, "reset should restart token_id counter")
    end)
  end)

  -- ===== 补测：_complete 路径（通过 timeout 回调触发） =====

  it("test_on_complete_invoked_when_timeout_fires", function()
    local completed = {}
    _with_schedule_capture(function(scheduled)
      effect_track.spawn("cue", "kind", 0.1, function(token)
        completed[#completed + 1] = token.id
      end)
      _assert_eq(#completed, 0, "on_complete should not fire before timeout")

      -- 执行 timeout 回调 = 调用 _complete
      scheduled[1].fn()
      _assert_eq(#completed, 1, "on_complete should fire after timeout")
      _assert_eq(completed[1], "cue", "on_complete should receive the correct token")
    end)
  end)

  it("test_cancel_returns_false_after_timeout_completes_token", function()
    _with_schedule_capture(function(scheduled)
      local token = effect_track.spawn("cue", "kind", 0.1, nil)
      _assert_eq(effect_track.cancel(token), true, "cancel before timeout should succeed")

      -- 第二个 token：先让 timeout 触发再尝试 cancel
      local token2 = effect_track.spawn("cue2", "kind", 0.1, nil)
      scheduled[#scheduled].fn() -- 这里的回调完成 token2（因为 spawn 会 schedule）
      _assert_eq(effect_track.is_idle(), true, "token2 should be completed by timeout")
      _assert_eq(effect_track.cancel(token2), false, "cancel after timeout completion should return false")
    end)
  end)

  it("test_is_idle_returns_true_after_timeout", function()
    _with_schedule_capture(function(scheduled)
      _assert_eq(effect_track.is_idle(), true, "should be idle initially")
      effect_track.spawn("cue", "kind", 0.1, nil)
      _assert_eq(effect_track.is_idle(), false, "should not be idle while token active")
      scheduled[1].fn()
      _assert_eq(effect_track.is_idle(), true, "should be idle after timeout cleans up")
    end)
  end)

  -- ===== 补测：await_all 空闲路径 =====

  it("test_await_all_when_idle_returns_true_and_invokes_callback_immediately", function()
    _with_runtime_port_mocks(function()
      local called = false
      local result = effect_track.await_all(function()
        called = true
      end)
      _assert_eq(result, true, "await_all when idle should return true")
      luassert.truthy(called, "callback should be invoked immediately when idle")
    end)
  end)

  it("test_await_all_when_idle_without_callback_returns_true", function()
    _with_runtime_port_mocks(function()
      local result = effect_track.await_all(nil)
      _assert_eq(result, true, "await_all when idle without callback should return true")
    end)
  end)

  -- ===== 补测：scaled_duration 与 _pressure 边界 =====

  it("test_scaled_duration_zero_pressure_returns_full_base", function()
    _with_runtime_port_mocks(function()
      -- 0 active tokens → pressure 0 → scale 1.0
      local result = effect_track.scaled_duration(2.0)
      _assert_eq(result, 2.0, "zero pressure should use 1.0 scale")
    end)
  end)

  it("test_scaled_duration_single_token_pressure_returns_full_base", function()
    _with_runtime_port_mocks(function()
      _spawn_active_tokens(1) -- count=1 → pressure 0
      local result = effect_track.scaled_duration(2.0)
      _assert_eq(result, 2.0, "single token pressure 0 should use 1.0 scale")
    end)
  end)

  it("test_scaled_duration_low_pressure_returns_half_base", function()
    _with_runtime_port_mocks(function()
      _spawn_active_tokens(2) -- count=2 ≤ 3 → pressure 0.3 → scale 0.5
      local result = effect_track.scaled_duration(2.0)
      _assert_eq(result, 1.0, "pressure 0.3 should halve base duration")
    end)
  end)

  it("test_scaled_duration_medium_pressure_returns_quarter_base", function()
    _with_runtime_port_mocks(function()
      _spawn_active_tokens(4) -- count=4 ≤ 6 → pressure 0.6 → scale 0.25
      local result = effect_track.scaled_duration(4.0)
      _assert_eq(result, 1.0, "pressure 0.6 should quarter base duration")
    end)
  end)

  it("test_scaled_duration_high_pressure_returns_min_scale_base", function()
    _with_runtime_port_mocks(function()
      _spawn_active_tokens(7) -- count=7 > 6 → pressure 0.9 → scale 0.15
      local result = effect_track.scaled_duration(10.0)
      _assert_eq(result, 1.5, "pressure 0.9 should use 0.15 scale")
    end)
  end)

  it("test_scaled_duration_hits_exact_threshold", function()
    _with_runtime_port_mocks(function()
      _spawn_active_tokens(3) -- count=3 ≤ 3 → pressure 0.3 → scale 0.5
      local result = effect_track.scaled_duration(3.0)
      _assert_eq(result, 1.5, "exact boundary count 3 should give pressure 0.3")
    end)
  end)

  it("test_scaled_duration_count_six_boundary", function()
    _with_runtime_port_mocks(function()
      _spawn_active_tokens(6) -- count=6 ≤ 6 → pressure 0.6 → scale 0.25
      local result = effect_track.scaled_duration(8.0)
      _assert_eq(result, 2.0, "exact boundary count 6 should give pressure 0.6")
    end)
  end)

end)
