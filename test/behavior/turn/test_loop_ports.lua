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

it("test__merge_required_ports_raises_missing_base_port_key_for_an_absent_base_port", function()
  -- kills the guard's message -> nil and tostring(key) -> nil mutants. The
  -- public resolve path never misses a base port; drive the guard directly.
  check.has_error(function()
    gameplay_loop_ports._M_test._merge_required_ports({}, {}, nil, { "ghost_port" })
  end, "missing base port: ghost_port")
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

it("test_build_noop_group_includes_extra_override_keys", function()
  local extra_fn = function() return "extra" end
  local group = gameplay_loop_ports._build_noop_group({ "a" }, { b = extra_fn })
  check.is_truthy(type(group.a) == "function", "declared key should still be present")
  _assert_eq(group.b, extra_fn, "extra key from overrides should be included")
end)

it("test_build_noop_group_returns_callable_noops", function()
  local group = gameplay_loop_ports._build_noop_group({ "x", "y" })
  check.is_truthy(type(group.x) == "function", "x should be a function")
  check.is_truthy(type(group.y) == "function", "y should be a function")
  _assert_eq(group.x(), nil, "noop x should return nil")
  _assert_eq(group.y(), nil, "noop y should return nil")
end)

it("test_build_noop_group_with_overrides_prefers_override", function()
  local custom = function() return 77 end
  local group = gameplay_loop_ports._build_noop_group({ "a", "b" }, { a = custom })
  _assert_eq(group.a, custom, "overridden key should be the custom fn")
  check.is_truthy(type(group.b) == "function", "non-overridden key should still be a function")
  _assert_eq(group.b(), nil, "non-overridden key should return nil")
end)

it("test_describe_contract_group_names_includes_all_groups", function()
  local contract = gameplay_loop_ports.describe_contract()
  local group_set = {}
  for _, name in ipairs(contract.group_names) do
    group_set[name] = true
  end
  for _, expected in ipairs({ "modal", "anim", "ui_sync", "debug", "clock", "state", "output" }) do
    check.is_truthy(group_set[expected] == true,
      "describe_contract group_names should include " .. expected)
  end
end)

it("test_describe_contract_port_groups_contain_expected_keys_per_group", function()
  local contract = gameplay_loop_ports.describe_contract()
  local function _keys_set(group_name)
    local set = {}
    for _, k in ipairs(contract.port_groups[group_name]) do set[k] = true end
    return set
  end
  local modal_keys = _keys_set("modal")
  check.is_truthy(modal_keys.close_choice_modal == true, "modal should include close_choice_modal")
  check.is_truthy(modal_keys.open_choice_modal == true, "modal should include open_choice_modal")
  local clock_keys = _keys_set("clock")
  check.is_truthy(clock_keys.wall_now_seconds == true, "clock should include wall_now_seconds")
  check.is_truthy(clock_keys.wall_diff_seconds == true, "clock should include wall_diff_seconds")
  check.is_truthy(clock_keys.cpu_now_seconds == true, "clock should include cpu_now_seconds")
  local output_keys = _keys_set("output")
  for _, expected in ipairs({
    "invalidate_ui_model", "clear_ui_dirty", "is_ui_dirty",
    "sync_ui_model", "get_ui_model",
    "sync_pending_choice", "clear_pending_choice", "get_pending_choice",
    "get_pending_choice_id", "get_pending_choice_elapsed",
    "set_pending_choice_elapsed", "set_pending_choice_id",
    "sync_modal_timer", "get_modal_elapsed", "get_modal_ref",
  }) do
    check.is_truthy(output_keys[expected] == true, "output should include " .. expected)
  end
  local state_keys = _keys_set("state")
  for _, expected in ipairs({
    "apply_role_control_lock", "install_event_handlers", "on_bankruptcy_tiles_cleared",
  }) do
    check.is_truthy(state_keys[expected] == true, "state should include " .. expected)
  end
end)

it("test_describe_contract_returns_independent_copies", function()
  local contract1 = gameplay_loop_ports.describe_contract()
  local contract2 = gameplay_loop_ports.describe_contract()
  check.is_truthy(contract1.group_names ~= contract2.group_names,
    "each describe_contract call should return fresh group_names")
  check.is_truthy(contract1.port_groups.modal ~= contract2.port_groups.modal,
    "each describe_contract call should return fresh port_groups.modal")
end)

it("test_describe_contract_ui_sync_keys_are_complete_and_ordered", function()
  -- kills the ui_sync port_groups key string -> nil mutants: a nil entry
  -- truncates the ipairs copy, so both length and per-position values shift.
  local contract = gameplay_loop_ports.describe_contract()
  local expected = {
    "apply_input_lock",
    "step_choice_timeout",
    "step_modal_timeout",
    "update_countdown",
    "resolve_ui_gate",
    "build_model",
    "refresh_from_dirty",
    "follow_camera",
    "sync_camera_position",
    "get_ui_state",
    "is_input_blocked",
    "is_popup_active",
    "is_choice_active",
    "get_popup_owner_index",
    "set_input_blocked",
    "probe_choice_ui_missing",
  }
  local actual = contract.port_groups.ui_sync
  _assert_eq(#actual, #expected, "ui_sync port key count must be complete")
  for i, key in ipairs(expected) do
    _assert_eq(actual[i], key, "ui_sync port key at position " .. i)
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
