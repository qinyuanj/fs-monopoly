local check = require("luassert")
local loop_runtime = require("src.turn.loop.runtime")
local runtime_state = require("src.state.runtime")
local tip_queue = require("src.foundation.tips")
local _config_reset = require("test.support.config_reset")

local function _assert_eq(a, b, msg)
  check.equal(a, b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

local function _make_state()
  return {}
end

describe("TestLoopRuntime", function()

before_each(function()
  _config_reset.reset_all()
end)

it("test_board_visual_feedback_port_defers_board_sync_before_popup", function()
  -- #293: L92/L175 的 key 翻 nil 变异把 priority 打回 100,board_visual_sync 与
  -- popup 的重放顺序翻转——钉住 hold 内 defer 时 board 必须先于 popup 重放。
  local landing_visual_hold = require("src.state.visual_hold")
  local calls = {}
  local state = _make_state()
  state.on_board_visual_sync = function(_, payload)
    calls[#calls + 1] = "board"
    return true
  end
  state.push_popup = function()
    calls[#calls + 1] = "popup"
    return true
  end
  runtime_state.set_landing_visual_hold_active(state, true)
  local game = {
    turn = {
      landing_visual_hold_active = true,
      landing_visual_release_pending = true,
    },
  }
  local board_port = loop_runtime.build_board_visual_feedback_port(state)
  local popup_port = loop_runtime.build_popup_port(state)
  local result1 = board_port.sync_many(nil, { tile_ids = { 1 } })
  local result2 = popup_port.push_popup(nil, { title = "hi" })
  _assert_eq(result1, true, "deferred board sync should register for replay")
  _assert_eq(result2, true, "deferred popup should register for replay")
  landing_visual_hold.release(state, game)
  _assert_eq(table.concat(calls, ","), "board,popup", "board visual sync must replay before popup")
end)

it("test_board_visual_feedback_port_sync_many_deferred_callback_reports_true", function()
  -- #293: L163(_board_visual_sync_deferred 的 type 检查翻反 / ==true 翻 false)
  -- 在有回调且回调返回 true 时必须如实上报 true。
  local state = _make_state()
  state.on_board_visual_sync = function() return true end
  local port = loop_runtime.build_board_visual_feedback_port(state)
  local result = port.sync_many({}, nil)
  _assert_eq(result, true, "a callback returning true should report true")
end)

it("test_board_visual_feedback_port_sync_many_method_call_form", function()
  -- #293: L154 _sync_many_args 的 type/==/and 变异会把两参方法式 (port, game)
  -- 误判为直调——arg3 缺席时 arg1 必须仍被识别为 self port,arg2 作 game 落进
  -- state.game。
  local state = _make_state()
  state.on_board_visual_sync = function() return true end
  local port = loop_runtime.build_board_visual_feedback_port(state)
  local game = { turn = {} }
  local result = port.sync_many(port, game)
  _assert_eq(result, true, "two-arg method-form sync_many should replay the deferred callback")
  _assert_eq(state.game, game, "two-arg method-form should treat arg1 as the port and arg2 as the game")
end)

it("test_board_visual_feedback_port_sync_many_uses_passed_game_for_state_game", function()
  -- #293: L171(game or state.game 翻 and)丢掉显式传入的 game;L172(~= 翻 ==)
  -- 在显式传 game 时不更新 state.game——显式 game 必须落进 state.game。
  local state = _make_state()
  state.on_board_visual_sync = function() return true end
  local port = loop_runtime.build_board_visual_feedback_port(state)
  local explicit = { turn = {} }
  local result = port.sync_many(explicit, nil)
  _assert_eq(result, true, "explicit game should drive the deferred sync")
  _assert_eq(state.game, explicit, "state.game should be updated to the passed game")
end)

it("test_build_anim_gate_port_cached_on_second_call", function()
  local state = _make_state()
  local port1 = loop_runtime.build_anim_gate_port(state)
  local port2 = loop_runtime.build_anim_gate_port(state)
  _assert_eq(port1, port2, "second call should return cached port")
end)

it("test_build_anim_gate_port_flags_false_when_not_set", function()
  local state = _make_state()
  local port = loop_runtime.build_anim_gate_port(state)
  _assert_eq(port.wait_move_anim, false, "wait_move_anim should be false when not set")
  _assert_eq(port.wait_action_anim, false, "wait_action_anim should be false when not set")
end)

it("test_build_anim_gate_port_returns_table_with_flags", function()
  local state = _make_state()
  state.wait_move_anim = true
  state.wait_action_anim = true
  local port = loop_runtime.build_anim_gate_port(state)
  _assert_eq(port.wait_move_anim, true, "wait_move_anim should reflect state")
  _assert_eq(port.wait_action_anim, true, "wait_action_anim should reflect state")
end)

it("test_build_board_scene_port_cached_on_second_call", function()
  local state = _make_state()
  local port1 = loop_runtime.build_board_scene_port(state)
  local port2 = loop_runtime.build_board_scene_port(state)
  _assert_eq(port1, port2, "second call should return cached port")
end)

it("test_build_board_scene_port_get_board_scene_returns_state_board_scene", function()
  local state = _make_state()
  state.board_scene = { some_scene = true }
  local port = loop_runtime.build_board_scene_port(state)
  _assert_eq(port.get_board_scene(), state.board_scene, "get_board_scene should return state.board_scene")
end)

it("test_build_board_scene_port_returns_table", function()
  local state = _make_state()
  local port = loop_runtime.build_board_scene_port(state)
  check.is_table(port, "should return a port table")
  check.is_function(port.get_board_scene, "should have get_board_scene")
end)

it("test_build_board_visual_feedback_port_cached_on_second_call", function()
  local state = _make_state()
  local port1 = loop_runtime.build_board_visual_feedback_port(state)
  local port2 = loop_runtime.build_board_visual_feedback_port(state)
  _assert_eq(port1, port2, "second call should return cached port")
end)

it("test_build_board_visual_feedback_port_returns_table", function()
  local state = _make_state()
  local port = loop_runtime.build_board_visual_feedback_port(state)
  check.is_table(port, "should return a port table")
  check.is_function(port.sync_many, "should have sync_many")
end)

it("test_build_board_visual_feedback_port_sync_many_no_callback_returns_false", function()
  local state = _make_state()
  state.on_board_visual_sync = nil
  local port = loop_runtime.build_board_visual_feedback_port(state)
  local result = port.sync_many({}, nil)
  _assert_eq(result, false, "sync_many with no callback should return false")
end)

it("test_build_popup_port_cached_on_second_call", function()
  local state = _make_state()
  local port1 = loop_runtime.build_popup_port(state)
  local port2 = loop_runtime.build_popup_port(state)
  _assert_eq(port1, port2, "second call should return cached port")
end)

it("test_build_popup_port_push_popup_returns_false_when_no_push_popup_fn", function()
  local state = _make_state()
  state.push_popup = nil
  local port = loop_runtime.build_popup_port(state)
  local result = port.push_popup(nil, {}, {})
  _assert_eq(result, false, "push_popup should return false when state has no push_popup function")
end)

it("test_build_popup_port_returns_table_with_push_popup", function()
  local state = _make_state()
  local port = loop_runtime.build_popup_port(state)
  check.is_table(port, "should return a port table")
  check.is_function(port.push_popup, "should have push_popup function")
end)

it("test_build_tile_feedback_port_cached_on_second_call", function()
  local state = _make_state()
  local port1 = loop_runtime.build_tile_feedback_port(state)
  local port2 = loop_runtime.build_tile_feedback_port(state)
  _assert_eq(port1, port2, "second call should return cached port")
end)

it("test_build_tile_feedback_port_forwards_sync_many_result", function()
  -- #293: L136 把 on_tile_upgraded 的 sync_many 调用翻 nil——game 挂反馈端口时
  -- 必须转发 sync_many 的返回值。
  local state = _make_state()
  local sync_called = false
  state.game = {
    board_visual_feedback_port = {
      sync_many = function(_, payload)
        sync_called = true
        return true
      end,
    },
  }
  local port = loop_runtime.build_tile_feedback_port(state)
  local result = port.on_tile_upgraded(nil, 3, 2)
  _assert_eq(result, true, "on_tile_upgraded should forward the sync_many result")
  _assert_eq(sync_called, true, "on_tile_upgraded should call the game feedback port")
end)

it("test_build_tile_feedback_port_no_game_returns_false", function()
  local state = _make_state()
  state.game = nil
  local port = loop_runtime.build_tile_feedback_port(state)
  local result = port.on_tile_upgraded(nil, 1, 2)
  _assert_eq(result, false, "no game should return false")
end)

it("test_build_tile_feedback_port_returns_table", function()
  local state = _make_state()
  local port = loop_runtime.build_tile_feedback_port(state)
  check.is_table(port, "should return a port table")
  check.is_function(port.on_tile_upgraded, "should have on_tile_upgraded")
end)

it("test_build_tip_output_port_cached_on_second_call", function()
  local state = _make_state()
  local port1 = loop_runtime.build_tip_output_port(state)
  local port2 = loop_runtime.build_tip_output_port(state)
  _assert_eq(port1, port2, "second call should return cached port")
end)

it("test_build_tip_output_port_enqueue_calls_show_tip", function()
  local state = _make_state()
  local called_with
  state.show_tip = function(_, intent)
    called_with = intent
    return true
  end
  local port = loop_runtime.build_tip_output_port(state)
  local result = port.enqueue(nil, { text = "hello" })
  _assert_eq(result, true, "enqueue should return true when show_tip returns true")
  _assert_eq(called_with.text, "hello", "show_tip should receive the intent")
end)

it("test_build_tip_output_port_enqueue_falls_back_to_tip_queue_when_no_show_tip", function()
  tip_queue.clear()
  local warns = {}
  local support = require("test.support.shared_support")
  local logger = require("src.foundation.log")
  local state = _make_state()
  local port
  local result
  support.with_patches({
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    port = loop_runtime.build_tip_output_port(state)
    result = port.enqueue(nil, { text = "hi" })
  end)
  _assert_eq(result, true, "enqueue should fall back to tip_queue and return true for valid intent when show_tip is missing")
  _assert_eq(warns[1]:find("show_tip not installed", 1, true) ~= nil, true,
    "fallback should leave a warn naming the missing show_tip")
  _assert_eq(warns[1]:find("[tip_output_port]", 1, true) ~= nil, true,
    "fallback warn should carry the port context")
  tip_queue.clear()
end)

it("test_popup_port_keeps_its_priority_above_low_priority_callbacks", function()
  -- #293: L92 的 key 翻 nil 变异把 popup 的 priority 从 6 打回 100——与内置
  -- key 混排时无法区分(popup 本就在末位),但 priority 在 6~100 之间的显式
  -- 回调能钉住:popup 必须先于它重放。
  local landing_visual_hold = require("src.state.visual_hold")
  local calls = {}
  local state = _make_state()
  state.push_popup = function()
    calls[#calls + 1] = "popup"
    return true
  end
  runtime_state.set_landing_visual_hold_active(state, true)
  local game = {
    turn = {
      landing_visual_hold_active = true,
      landing_visual_release_pending = true,
    },
  }
  local popup_port = loop_runtime.build_popup_port(state)
  landing_visual_hold.register_release_callback(state, "custom", function()
    calls[#calls + 1] = "custom"
  end, { priority = 50 })
  local result = popup_port.push_popup(nil, { title = "hi" })
  _assert_eq(result, true, "deferred popup should register for replay")
  landing_visual_hold.release(state, game)
  _assert_eq(table.concat(calls, ","), "popup,custom", "popup must replay before lower-priority callbacks")
end)

it("test_sync_input_blocked_blocked_phase_passes_true", function()
  local state = _make_state()
  local received_blocked
  local ports = {
    ui_sync = {
      get_ui_state = function() return { ui = true } end,
      set_input_blocked = function(_, blocked)
        received_blocked = blocked
        return true
      end,
    },
  }
  local result = loop_runtime.sync_input_blocked(state, "wait_action_anim", ports)
  _assert_eq(result, true, "blocked phase with set returning true should return true")
  _assert_eq(received_blocked, true, "set_input_blocked should receive true for blocked phase")
end)

it("test_sync_input_blocked_missing_get_ui_state_returns_false", function()
  local state = _make_state()
  local ports = { ui_sync = { set_input_blocked = function() end } }
  local result = loop_runtime.sync_input_blocked(state, "pre_move", ports)
  _assert_eq(result, false, "missing get_ui_state should return false")
end)

it("test_sync_input_blocked_nil_ui_returns_false", function()
  local state = _make_state()
  local ports = {
    ui_sync = {
      get_ui_state = function() return nil end,
      set_input_blocked = function() return true end,
    },
  }
  local result = loop_runtime.sync_input_blocked(state, "pre_move", ports)
  _assert_eq(result, false, "nil ui_state should return false")
end)

it("test_sync_input_blocked_no_ports_returns_false", function()
  local state = _make_state()
  local result = loop_runtime.sync_input_blocked(state, "wait_move_anim", nil)
  _assert_eq(result, false, "nil ports should return false")
end)

it("test_sync_input_blocked_no_ui_sync_returns_false", function()
  local state = _make_state()
  local result = loop_runtime.sync_input_blocked(state, "wait_move_anim", { other = true })
  _assert_eq(result, false, "ports without ui_sync should return false")
end)

it("test_sync_input_blocked_set_returns_false_propagates", function()
  local state = _make_state()
  local ports = {
    ui_sync = {
      get_ui_state = function() return { some = "ui" } end,
      set_input_blocked = function() return false end,
    },
  }
  local result = loop_runtime.sync_input_blocked(state, "wait_move_anim", ports)
  _assert_eq(result, false, "set_input_blocked returning false should propagate")
end)

it("test_sync_input_blocked_unblocked_phase_passes_false", function()
  local state = _make_state()
  local received_blocked
  local ports = {
    ui_sync = {
      get_ui_state = function() return { ui = true } end,
      set_input_blocked = function(_, blocked)
        received_blocked = blocked
        return true
      end,
    },
  }
  loop_runtime.sync_input_blocked(state, "pre_move", ports)
  _assert_eq(received_blocked, false, "set_input_blocked should receive false for non-blocked phase")
end)

it("test_sync_phase_flags_keeps_lock_when_lock_phase_missing", function()
  -- #293: L49 位点 1(or 变异)在 locked 但 lock_phase 缺失时也会解锁——
  -- 缺记录的锁不得被解除。
  local state = _make_state()
  loop_runtime.sync_phase_flags(state, "move")
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  turn_runtime.next_turn_locked = true
  turn_runtime.next_turn_lock_phase = nil
  loop_runtime.sync_phase_flags(state, "move")
  _assert_eq(turn_runtime.next_turn_locked, true, "a lock without a recorded phase must not be unlocked")
end)

it("test_sync_phase_flags_keeps_lock_when_phase_matches_lock_phase", function()
  -- #293: L49 _should_unlock_next_turn 的 and→or 变异(位点 2/3)会在同相位时
  -- 谎报解锁——锁必须只在相位真正变化时解除。
  local state = _make_state()
  loop_runtime.sync_phase_flags(state, "move")
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  turn_runtime.next_turn_locked = true
  turn_runtime.next_turn_lock_phase = "move"
  loop_runtime.sync_phase_flags(state, "move")
  _assert_eq(turn_runtime.next_turn_locked, true, "same phase must not unlock the next-turn lock")
end)

it("test_sync_phase_flags_same_wait_move_anim_no_sync_pending", function()
  local state = _make_state()
  loop_runtime.sync_phase_flags(state, "wait_move_anim")
  loop_runtime.sync_phase_flags(state, "wait_move_anim")
  local board_runtime = runtime_state.ensure_board_runtime(state)
  check.is_truthy(not board_runtime.board_sync_pending, "staying in wait_move_anim should not set board_sync_pending")
end)

it("test_sync_phase_flags_sets_board_last_phase", function()
  local state = _make_state()
  loop_runtime.sync_phase_flags(state, "pre_move")
  local board_runtime = runtime_state.ensure_board_runtime(state)
  _assert_eq(board_runtime.board_last_phase, "pre_move", "board_last_phase should be set")
end)

it("test_sync_phase_flags_transitions_from_wait_move_anim_sets_board_sync_pending", function()
  local state = _make_state()
  loop_runtime.sync_phase_flags(state, "wait_move_anim")
  loop_runtime.sync_phase_flags(state, "pre_move")
  local board_runtime = runtime_state.ensure_board_runtime(state)
  _assert_eq(board_runtime.board_sync_pending, true, "leaving wait_move_anim should set board_sync_pending")
end)

it("test_sync_phase_flags_unlocks_next_turn_lock_on_phase_change", function()
  local state = _make_state()
  loop_runtime.sync_phase_flags(state, "pre_move")
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  turn_runtime.next_turn_locked = true
  turn_runtime.next_turn_lock_phase = "pre_move"
  loop_runtime.sync_phase_flags(state, "move")
  _assert_eq(turn_runtime.next_turn_locked, false, "changing phase should unlock next_turn_locked")
end)


end)
