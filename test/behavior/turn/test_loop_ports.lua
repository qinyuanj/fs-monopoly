local check = require("luassert")
local gameplay_loop_ports = require("src.turn.loop.ports")
local _config_reset = require("test.support.config_reset")

local function _assert_eq(a, b, msg)
  check.equal(a, b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

describe("TestLoopPorts", function()

before_each(function()
  _config_reset.reset_all()
end)

it("test_base_anim_ports_are_no_op_when_invoked", function()
  local ports = gameplay_loop_ports.resolve(nil)
  _assert_eq(ports.anim.play_move_anim(), nil, "play_move_anim noop returns nil")
  _assert_eq(ports.anim.play_action_anim(), nil, "play_action_anim noop returns nil")
  _assert_eq(ports.anim.reset_status_3d(), nil, "reset_status_3d noop returns nil")
  _assert_eq(ports.anim.sync_status_3d(), nil, "sync_status_3d noop returns nil")
end)

it("test_base_clock_ports_return_zero_for_now_and_zero_for_diff_with_nil_args", function()
  local ports = gameplay_loop_ports.resolve(nil)
  _assert_eq(ports.clock.wall_now_seconds(), 0, "wall_now_seconds returns 0")
  _assert_eq(ports.clock.cpu_now_seconds(), 0, "cpu_now_seconds returns 0")
  _assert_eq(ports.clock.wall_diff_seconds(nil, 1.0), 0, "wall_diff with nil first arg returns 0")
  _assert_eq(ports.clock.cpu_diff_seconds(2.0, nil), 0, "cpu_diff with nil second arg returns 0")
  _assert_eq(ports.clock.wall_diff_seconds(5.0, 3.0), 2.0, "wall_diff with both numeric args returns difference")
  _assert_eq(ports.clock.cpu_diff_seconds(10.0, 1.5), 8.5, "cpu_diff with both numeric args returns difference")
end)

it("test_base_debug_ports_are_no_op_except_resolve_event_log_enabled_returns_false", function()
  local ports = gameplay_loop_ports.resolve(nil)
  _assert_eq(ports.debug.sync_event_log(), nil, "sync_event_log noop returns nil")
  _assert_eq(ports.debug.resolve_event_log_enabled(), false, "resolve_event_log_enabled returns false")
end)

it("test_base_debug_resolve_event_log_enabled_returns_false", function()
  -- kills the base builder's `return false` -> true.
  local ports = gameplay_loop_ports.resolve(nil)
  _assert_eq(ports.debug.resolve_event_log_enabled(), false,
    "the base debug port never enables the event log")
end)

it("test_base_modal_ports_are_no_op_and_return_nil_when_invoked", function()
  local ports = gameplay_loop_ports.resolve(nil)
  _assert_eq(ports.modal.close_choice_modal(), nil, "close_choice_modal noop returns nil")
  _assert_eq(ports.modal.open_choice_modal(), nil, "open_choice_modal noop returns nil")
  _assert_eq(ports.modal.close_popup(), nil, "close_popup noop returns nil")
end)

it("test_base_output_port_invalidate_ui_model_actually_toggles_dirty_flag", function()
  local ports = gameplay_loop_ports.resolve(nil)
  local state = {}
  _assert_eq(ports.output.is_ui_dirty(state), false, "fresh state not dirty")
  _assert_eq(ports.output.invalidate_ui_model(state), true, "first invalidate returns true")
  _assert_eq(ports.output.is_ui_dirty(state), true, "state dirty after invalidate")
  _assert_eq(ports.output.invalidate_ui_model(state), false, "second invalidate returns false (already dirty)")
end)

it("test_base_state_ports_are_no_op_when_invoked", function()
  local ports = gameplay_loop_ports.resolve(nil)
  _assert_eq(ports.state.apply_role_control_lock(), nil, "apply_role_control_lock noop returns nil")
  _assert_eq(ports.state.install_event_handlers(), nil, "install_event_handlers noop returns nil")
  _assert_eq(ports.state.on_bankruptcy_tiles_cleared(), nil, "on_bankruptcy_tiles_cleared noop returns nil")
end)

it("test_base_ui_sync_ports_include_all_declared_keys_as_functions", function()
  local ports = gameplay_loop_ports.resolve(nil)
  local expected = {
    "apply_input_lock", "step_choice_timeout", "step_modal_timeout",
    "update_countdown", "resolve_ui_gate", "build_model", "refresh_from_dirty", "follow_camera",
    "sync_camera_position", "get_ui_state", "is_input_blocked",
    "is_popup_active", "is_choice_active",
    "get_popup_owner_index", "set_input_blocked",
    "probe_choice_ui_missing",
  }
  for _, key in ipairs(expected) do
    check.is_truthy(type(ports.ui_sync[key]) == "function",
      "ui_sync." .. key .. " should be a function")
  end
end)

it("test_override_on_debug_group_preserves_resolve_event_log_enabled_override", function()
  local ports = gameplay_loop_ports.resolve({
    debug = { resolve_event_log_enabled = function() return true end },
  })
  _assert_eq(ports.debug.resolve_event_log_enabled(), true, "overridden debug return value applies")
end)

it("test_override_on_output_group_custom_invalidate_is_used_others_fallback", function()
  local custom_called = 0
  local custom_invalidate = function() custom_called = custom_called + 1; return "custom" end
  local ports = gameplay_loop_ports.resolve({
    output = { invalidate_ui_model = custom_invalidate },
  })
  local result = ports.output.invalidate_ui_model({})
  _assert_eq(custom_called, 1, "custom invalidate should be called")
  _assert_eq(result, "custom", "custom return propagates")
  check.is_truthy(type(ports.output.sync_ui_model) == "function",
    "sync_ui_model should remain base function (not overridden)")
end)

it("test_repeated_resolve_nil_returns_independent_group_tables_no_shared_mutation", function()
  local ports1 = gameplay_loop_ports.resolve(nil)
  local ports2 = gameplay_loop_ports.resolve(nil)
  check.is_truthy(ports1 ~= ports2, "each resolve should return new top-level table")
  check.is_truthy(ports1.modal ~= ports2.modal, "modal group should be independent")
  check.is_truthy(ports1.output ~= ports2.output, "output group should be independent")
end)

it("test_resolve_empty_table_returns_base_ports", function()
  local ports = gameplay_loop_ports.resolve({})
  check.is_truthy(type(ports.modal) == "table", "resolve({}) should include modal group")
  check.is_truthy(type(ports.modal.close_choice_modal) == "function",
    "modal group should have close_choice_modal fn")
end)

it("test_resolve_non_table_override_errors", function()
  local ok, _ = pcall(function()
    gameplay_loop_ports.resolve("not_a_table")
  end)
  _assert_eq(ok, false, "non-table override should raise an error")
end)

it("test_resolve_override_extra_keys_included", function()
  local extra_fn = function() return "extra" end
  local ports = gameplay_loop_ports.resolve({
    modal = {
      open_choice_modal = function() end,
      extra_non_required_key = extra_fn,
    },
  })
  _assert_eq(ports.modal.extra_non_required_key, extra_fn,
    "extra key in override group should be included in resolved ports")
end)

it("test_resolve_rejects_a_non_table_override_with_its_guard_message", function()
  -- kills resolve's "invalid gameplay_loop_ports override: expected table" -> nil.
  check.has_error(function()
    gameplay_loop_ports.resolve("not a table")
  end, "invalid gameplay_loop_ports override: expected table")
end)

it("test_resolve_table_without_group_keys_uses_base_ports", function()
  local ports = gameplay_loop_ports.resolve({ some_other_key = "value" })
  check.is_truthy(type(ports.modal) == "table", "no-group-key table should use base modal ports")
  check.is_truthy(type(ports.clock.wall_now_seconds) == "function",
    "no-group-key table should use base clock ports")
end)


end)
