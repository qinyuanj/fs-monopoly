require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local with_patches = support.with_patches
local game_runtime_bootstrap = require("src.app.gameplay_start")
local gameplay_loop = require("src.turn.loop")
local presentation_ports = require("src.ui.ports")
local frame_timer = require("src.host.frame_timer")

local function _assert_close(actual, expected, epsilon, msg)
  local delta = math.abs((actual or 0) - (expected or 0))
  luassert.truthy(delta <= epsilon, (msg or "value mismatch") .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
end

local function _common_start_patches(capture, clock)
  return {
    {
      target = frame_timer,
      key = "repeat_every",
      value = function(_, cb)
        capture.tick_callback = cb
      end,
    },
    {
      target = presentation_ports,
      key = "build",
      value = function()
        return {
          clock = clock,
          debug = {},
        }
      end,
    },
    {
      target = gameplay_loop,
      key = "new_game",
      value = function()
        return {
          logger = { info = function() end },
        }
      end,
    },
    {
      target = gameplay_loop,
      key = "set_game",
      value = function() end,
    },
    {
      target = gameplay_loop,
      key = "tick",
      value = function(_, _, dt)
        capture.dt_values[#capture.dt_values + 1] = dt
      end,
    },
  }
end

describe("TestRuntimeBootstrap", function()

local function _test_frame_timer_repeat_every_registers_repeat_timeout_with_frame_interval()
  -- 直测 host adapter 本体(本 spec 其余用例全部 stub 它):钉死 RegisterTriggerEvent
  -- 调用形状——EVENT.REPEAT_TIMEOUT + interval(帧)/30.0 秒换算(Fixed 浮点)+ 回调透传。
  local captured = {}
  local callback = function() end
  with_patches({
    { key = "EVENT", value = { REPEAT_TIMEOUT = "repeat_timeout" } },
    { target = math, key = "tofixed", value = function(v)
      return v
    end },
    { key = "RegisterTriggerEvent", value = function(args, cb)
      captured.args = args
      captured.cb = cb
      return 47
    end },
    { key = "UnregisterTriggerEvent", value = function(trigger_id)
      captured.unregistered_id = trigger_id
      captured.unregister_calls = (captured.unregister_calls or 0) + 1
    end },
  }, function()
    local handle = frame_timer.repeat_every(3, callback)
    frame_timer.stop(handle)
    frame_timer.stop(handle)
  end)

  luassert.truthy(captured.args[1] == "repeat_timeout", "registers EVENT.REPEAT_TIMEOUT")
  _assert_close(captured.args[2], 3 / 30.0, 1e-9, "frame interval converts to seconds at 30fps")
  luassert.truthy(captured.cb == callback, "callback passes through unchanged")
  luassert.is.equal(47, captured.unregistered_id, "stop should unregister the returned trigger id")
  luassert.is.equal(1, captured.unregister_calls, "stop should be idempotent for the same handle")
end

local function _test_frame_timer_repeat_every_rejects_non_function_callback()
  luassert.has_error(function()
    frame_timer.repeat_every(3, nil)
  end, "frame_timer.repeat_every requires callback")
end

local function _test_runtime_bootstrap_uses_wall_clock_diff_after_first_tick()
  local capture = { tick_callback = nil, dt_values = {} }
  local now_values = { 100, 100.05 }
  local now_index = 0
  local clock = {
    wall_now_seconds = function()
      now_index = now_index + 1
      return now_values[now_index] or now_values[#now_values]
    end,
    wall_diff_seconds = function(current, previous)
      return current - previous
    end,
    cpu_now_seconds = function()
      return 0
    end,
    cpu_diff_seconds = function(current, previous)
      return current - previous
    end,
  }

  with_patches(_common_start_patches(capture, clock), function()
    local state = {}
    local game_ref = { nil }
    game_runtime_bootstrap.start(state, game_ref)
    luassert.truthy(type(capture.tick_callback) == "function", "tick callback should be registered")
    capture.tick_callback()
    capture.tick_callback()
  end)

  luassert.truthy(#capture.dt_values == 2, "tick callback should produce two dt samples")
  _assert_close(capture.dt_values[1], 1.0 / 30.0, 0.0001, "first tick should fallback to fixed delta")
  _assert_close(capture.dt_values[2], 0.05, 0.0001, "second tick should use wall clock diff delta")
end

local function _test_runtime_bootstrap_sets_game_before_priming_first_turn()
  local capture = {
    tick_callback = nil,
    dt_values = {},
    primed_game = nil,
    set_game_received = nil,
    call_order = {},
  }
  local clock = {
    wall_now_seconds = function()
      return 0
    end,
    wall_diff_seconds = function()
      return 0
    end,
    cpu_now_seconds = function()
      return 0
    end,
    cpu_diff_seconds = function(current, previous)
      return current - previous
    end,
  }
  local primed_game = {
    logger = { info = function() end },
    turn = {
      turn_count = 0,
      phase = "start",
      pending_choice = nil,
    },
    advance_turn = function(self)
      self.turn.turn_count = 1
      self.turn.phase = "wait_action"
      capture.primed_game = self
      capture.call_order[#capture.call_order + 1] = "prime"
    end,
  }

  with_patches({
    {
      target = frame_timer,
      key = "repeat_every",
      value = function(_, cb)
        capture.tick_callback = cb
      end,
    },
    {
      target = presentation_ports,
      key = "build",
      value = function()
        return {
          clock = clock,
          debug = {},
        }
      end,
    },
    {
      target = gameplay_loop,
      key = "new_game",
      value = function()
        return primed_game
      end,
    },
    {
      target = gameplay_loop,
      key = "set_game",
      value = function(_, game)
        capture.set_game_received = game
        capture.call_order[#capture.call_order + 1] = "set_game"
      end,
    },
    {
      target = gameplay_loop,
      key = "tick",
      value = function(_, _, dt)
        capture.dt_values[#capture.dt_values + 1] = dt
      end,
    },
  }, function()
    local state = {}
    local game_ref = { nil }
    local started = game_runtime_bootstrap.start(state, game_ref)
    luassert.truthy(started == primed_game, "start should return the created game")
  end)

  luassert.truthy(capture.primed_game == primed_game, "runtime bootstrap should prime the first turn on startup")
  luassert.truthy(capture.set_game_received == primed_game, "set_game should receive the primed game instance")
  -- set_game 会 reset wait_callback_runtime,排在首回合之后就会抹掉首回合挂起的
  -- landing_visual 等待凭证,真机上整局死锁在 wait_landing_visual。
  luassert.truthy(capture.call_order[1] == "set_game", "set_game must run before the first turn is primed")
  luassert.truthy(capture.call_order[2] == "prime", "first turn must be primed after set_game")
  luassert.truthy(primed_game.turn.turn_count == 1, "primed startup game should increment first turn count")
  luassert.truthy(primed_game.turn.phase == "wait_action", "primed startup game should reach wait_action before rendering")
end

local function _test_runtime_bootstrap_falls_back_when_wall_clock_unavailable()
  local capture = { tick_callback = nil, dt_values = {} }
  local clock = {
    wall_now_seconds = function()
      return nil
    end,
    wall_diff_seconds = function()
      return nil
    end,
    cpu_now_seconds = function()
      return 0
    end,
    cpu_diff_seconds = function(current, previous)
      return current - previous
    end,
  }

  with_patches(_common_start_patches(capture, clock), function()
    local state = {}
    local game_ref = { nil }
    game_runtime_bootstrap.start(state, game_ref)
    luassert.truthy(type(capture.tick_callback) == "function", "tick callback should be registered")
    capture.tick_callback()
  end)

  luassert.truthy(#capture.dt_values == 1, "tick callback should produce one dt sample")
  _assert_close(capture.dt_values[1], 1.0 / 30.0, 0.0001, "invalid wall clock should fallback to fixed delta")
end

local function _test_runtime_bootstrap_uses_raw_diff_when_wall_diff_returns_zero()
  local capture = { tick_callback = nil, dt_values = {} }
  local now_values = { 10.00, 10.08 }
  local now_index = 0
  local clock = {
    wall_now_seconds = function()
      now_index = now_index + 1
      return now_values[now_index] or now_values[#now_values]
    end,
    wall_diff_seconds = function()
      return 0
    end,
    cpu_now_seconds = function()
      return 0
    end,
    cpu_diff_seconds = function(current, previous)
      return current - previous
    end,
  }

  with_patches(_common_start_patches(capture, clock), function()
    local state = {}
    local game_ref = { nil }
    game_runtime_bootstrap.start(state, game_ref)
    capture.tick_callback()
    capture.tick_callback()
  end)

  luassert.truthy(#capture.dt_values == 2, "tick callback should produce two dt samples")
  _assert_close(capture.dt_values[1], 1.0 / 30.0, 0.0001, "first tick should fallback to fixed delta")
  _assert_close(capture.dt_values[2], 0.08, 0.0001, "second tick should fallback to raw timestamp diff")
end

local function _test_runtime_bootstrap_accepts_reversed_wall_diff()
  local capture = { tick_callback = nil, dt_values = {} }
  local now_values = { 20.00, 20.06 }
  local now_index = 0
  local clock = {
    wall_now_seconds = function()
      now_index = now_index + 1
      return now_values[now_index] or now_values[#now_values]
    end,
    wall_diff_seconds = function(a, b)
      return b - a
    end,
    cpu_now_seconds = function()
      return 0
    end,
    cpu_diff_seconds = function(current, previous)
      return current - previous
    end,
  }

  with_patches(_common_start_patches(capture, clock), function()
    local state = {}
    local game_ref = { nil }
    game_runtime_bootstrap.start(state, game_ref)
    capture.tick_callback()
    capture.tick_callback()
  end)

  luassert.truthy(#capture.dt_values == 2, "tick callback should produce two dt samples")
  _assert_close(capture.dt_values[1], 1.0 / 30.0, 0.0001, "first tick should fallback to fixed delta")
  _assert_close(capture.dt_values[2], 0.06, 0.0001, "second tick should accept reversed diff source")
end

local function _test_runtime_bootstrap_ignores_coarse_wall_clock()
  local capture = { tick_callback = nil, dt_values = {} }
  local now_values = { 123456, 123457, 123458 }
  local now_index = 0
  local clock = {
    wall_now_seconds = function()
      now_index = now_index + 1
      return now_values[now_index] or now_values[#now_values]
    end,
    wall_diff_seconds = function(current, previous)
      return current - previous
    end,
    cpu_now_seconds = function()
      return 0
    end,
    cpu_diff_seconds = function(current, previous)
      return current - previous
    end,
  }

  with_patches(_common_start_patches(capture, clock), function()
    local state = {}
    local game_ref = { nil }
    game_runtime_bootstrap.start(state, game_ref)
    capture.tick_callback()
    capture.tick_callback()
    capture.tick_callback()
  end)

  luassert.truthy(#capture.dt_values == 3, "tick callback should produce three dt samples")
  _assert_close(capture.dt_values[1], 1.0 / 30.0, 0.0001, "first tick should fallback to fixed delta")
  _assert_close(capture.dt_values[2], 1.0 / 30.0, 0.0001, "coarse wall clock should keep fixed delta")
  _assert_close(capture.dt_values[3], 1.0 / 30.0, 0.0001, "coarse wall clock should keep fixed delta")
end

local function _test_runtime_bootstrap_preserves_fractional_wall_clock_diff_across_many_ticks()
  local capture = { tick_callback = nil, dt_values = {} }
  local now_values = { 200.00, 200.03, 200.06, 200.09 }
  local now_index = 0
  local clock = {
    wall_now_seconds = function()
      now_index = now_index + 1
      return now_values[now_index] or now_values[#now_values]
    end,
    wall_diff_seconds = function(current, previous)
      return current - previous
    end,
    cpu_now_seconds = function()
      return 0
    end,
    cpu_diff_seconds = function(current, previous)
      return current - previous
    end,
  }

  with_patches(_common_start_patches(capture, clock), function()
    local state = {}
    local game_ref = { nil }
    game_runtime_bootstrap.start(state, game_ref)
    capture.tick_callback()
    capture.tick_callback()
    capture.tick_callback()
    capture.tick_callback()
  end)

  luassert.truthy(#capture.dt_values == 4, "tick callback should preserve each fractional dt sample")
  _assert_close(capture.dt_values[1], 1.0 / 30.0, 0.0001, "first tick should fallback to fixed delta")
  _assert_close(capture.dt_values[2], 0.03, 0.0001, "second tick should keep fractional wall diff")
  _assert_close(capture.dt_values[3], 0.03, 0.0001, "third tick should keep fractional wall diff")
  _assert_close(capture.dt_values[4], 0.03, 0.0001, "fourth tick should keep fractional wall diff")
end


it("test_frame_timer_repeat_every_registers_repeat_timeout_with_frame_interval", _test_frame_timer_repeat_every_registers_repeat_timeout_with_frame_interval)
it("test_frame_timer_repeat_every_rejects_non_function_callback", _test_frame_timer_repeat_every_rejects_non_function_callback)
it("test_runtime_bootstrap_uses_wall_clock_diff_after_first_tick", _test_runtime_bootstrap_uses_wall_clock_diff_after_first_tick)
it("test_runtime_bootstrap_sets_game_before_priming_first_turn", _test_runtime_bootstrap_sets_game_before_priming_first_turn)
it("test_runtime_bootstrap_falls_back_when_wall_clock_unavailable", _test_runtime_bootstrap_falls_back_when_wall_clock_unavailable)
it("test_runtime_bootstrap_uses_raw_diff_when_wall_diff_returns_zero", _test_runtime_bootstrap_uses_raw_diff_when_wall_diff_returns_zero)
it("test_runtime_bootstrap_accepts_reversed_wall_diff", _test_runtime_bootstrap_accepts_reversed_wall_diff)
it("test_runtime_bootstrap_ignores_coarse_wall_clock", _test_runtime_bootstrap_ignores_coarse_wall_clock)
it("test_runtime_bootstrap_preserves_fractional_wall_clock_diff_across_many_ticks", _test_runtime_bootstrap_preserves_fractional_wall_clock_diff_across_many_ticks)
end)
