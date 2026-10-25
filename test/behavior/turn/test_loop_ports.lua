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

it("test_state_reads_revalidate_group_and_root_replacements", function()
  local state = { gameplay_loop_ports = { debug = {} } }
  local first = gameplay_loop_ports.resolve_for_state(state)
  first.debug = { resolve_event_log_enabled = function() return true end }
  local replaced_group = gameplay_loop_ports.resolve_for_state(state)
  check.is_not.equal(first, replaced_group)
  check.is_true(replaced_group.debug.resolve_event_log_enabled())
  state.gameplay_loop_ports = { debug = {} }
  local replaced_root = gameplay_loop_ports.resolve_for_state(state)
  check.is_not.equal(replaced_group, replaced_root)
  check.is_false(replaced_root.debug.resolve_event_log_enabled())
  check.equal(replaced_root, gameplay_loop_ports.resolve_for_state(state))
end)

it("test_deleted_and_non_function_required_ports_fall_back", function()
  local state = { gameplay_loop_ports = {
    debug = { resolve_event_log_enabled = function() return true end },
  } }
  local first = gameplay_loop_ports.resolve_for_state(state)
  first.debug.resolve_event_log_enabled = nil
  local deleted = gameplay_loop_ports.resolve_for_state(state)
  check.is_false(deleted.debug.resolve_event_log_enabled())
  deleted.debug.sync_event_log = "not a function"
  local invalidated = gameplay_loop_ports.resolve_for_state(state)
  check.is_nil(invalidated.debug.sync_event_log())
  check.equal(invalidated, gameplay_loop_ports.resolve_for_state(state))
end)

it("test_resolve_returns_exactly_the_seven_declared_groups_and_keeps_caller_groups", function()
  -- #209：回合端口包只承载回合契约声明的 7 组，不再寄存 ui 自有分组。
  local close_choice_modal = function() return "caller" end
  local ports = gameplay_loop_ports.resolve({
    modal = { close_choice_modal = close_choice_modal },
    view_command = { dispatch = function() return true end },
    stray_group = { resolve_role_by_id = function() return nil end },
  })
  local names = {}
  for name in pairs(ports) do names[#names + 1] = name end
  table.sort(names)
  check.same({ "anim", "clock", "debug", "modal", "output", "state", "ui_sync" }, names)
  check.equal(close_choice_modal, ports.modal.close_choice_modal)
end)

it("test_state_reads_drop_undeclared_groups_once_resolved", function()
  local state = { gameplay_loop_ports = { debug = {}, view_command = { dispatch = function() end } } }
  local first = gameplay_loop_ports.resolve_for_state(state)
  check.is_nil(first.view_command)
  check.equal(first, state.gameplay_loop_ports)
  first.stray_group = { role_id = 42 }
  local reresolved = gameplay_loop_ports.resolve_for_state(state)
  check.is_not.equal(first, reresolved)
  check.is_nil(reresolved.stray_group)
  check.equal(reresolved, gameplay_loop_ports.resolve_for_state(state))
end)

it("test_extra_keys_survive_and_invalidate_state_reads", function()
  local state = { gameplay_loop_ports = { debug = {} } }
  local first = gameplay_loop_ports.resolve_for_state(state)
  first.debug.extra = false
  local added = gameplay_loop_ports.resolve_for_state(state)
  check.is_not.equal(first, added)
  check.is_false(added.debug.extra)
  added.debug.extra = nil
  local deleted = gameplay_loop_ports.resolve_for_state(state)
  check.is_not.equal(added, deleted)
  check.is_nil(deleted.debug.extra)
  check.equal(deleted, gameplay_loop_ports.resolve_for_state(state))
end)

it("test_invalid_gate_mutation_throws_until_repaired_without_committing", function()
  local gate = function() return { input_blocked = true } end
  local state = { gameplay_loop_ports = { ui_sync = {
    resolve_ui_gate = gate,
    is_input_blocked = function() return true end,
  } } }
  local first = gameplay_loop_ports.resolve_for_state(state)
  first.ui_sync.resolve_ui_gate = nil
  local ok, err = pcall(gameplay_loop_ports.resolve_for_state, state)
  check.is_false(ok)
  check.matches("lacks resolve_ui_gate", err, 1, true)
  check.equal(first, state.gameplay_loop_ports)
  check.is_false(pcall(gameplay_loop_ports.resolve_for_state, state))
  first.ui_sync.resolve_ui_gate = gate
  check.is_true(gameplay_loop_ports.resolve_for_state(state).ui_sync.is_input_blocked())
  state.gameplay_loop_ports = "invalid root"
  check.has_error(function() gameplay_loop_ports.resolve_for_state(state) end,
    "invalid gameplay_loop_ports override: expected table")
  state.gameplay_loop_ports = { debug = {} }
  check.is_false(gameplay_loop_ports.resolve_for_state(state).debug.resolve_event_log_enabled())
end)

it("test_interleaved_states_keep_current_ports_independent", function()
  local a, b = {}, {}
  local pa = gameplay_loop_ports.resolve_for_state(a)
  local pb = gameplay_loop_ports.resolve_for_state(b)
  check.is_not.equal(pa, pb)
  pa.debug.resolve_event_log_enabled = function() return true end
  local changed_a = gameplay_loop_ports.resolve_for_state(a)
  check.is_true(changed_a.debug.resolve_event_log_enabled())
  check.equal(pb, gameplay_loop_ports.resolve_for_state(b))
  check.is_false(pb.debug.resolve_event_log_enabled())
  check.equal(changed_a, gameplay_loop_ports.resolve_for_state(a))
  local public = gameplay_loop_ports.resolve(changed_a)
  check.is_not.equal(public, changed_a)
  check.is_not.equal(public.debug, changed_a.debug)
end)

it("test_cold_and_changed_state_reads_have_a_bounded_recompute_budget", function()
  -- #183 的重算/组复制预算是显式验收契约；debug hook 只观察真实调用，
  -- 不替换 resolve 或内部协作者，也不预置缓存。
  local merge = require("src.turn.loop.ports_merge")
  local resolutions, copies = 0, 0
  local previous, mask, count = debug.gethook()
  debug.sethook(function(event)
    if event ~= "call" then return end
    local fn = debug.getinfo(2, "f").func
    if fn == gameplay_loop_ports.resolve then resolutions = resolutions + 1 end
    if fn == merge.copy_group_ports then copies = copies + 1 end
  end, "c")
  local ok, err = pcall(function()
    local state = {}
    gameplay_loop_ports.resolve_for_state(state)
    for _ = 1, 10 do gameplay_loop_ports.resolve_for_state(state) end
    -- lint-allow: call-count #183 冷启动加稳定读取仅一次 memo 重算
    check.equal(1, resolutions)
    -- lint-allow: call-count #183 首次解析复制七组，稳定读取零组复制
    check.equal(7, copies)
    state.gameplay_loop_ports.debug.extra = "changed"
    gameplay_loop_ports.resolve_for_state(state)
    for _ = 1, 10 do gameplay_loop_ports.resolve_for_state(state) end
    -- lint-allow: call-count #183 一次实际配置变化仅一次完整重算
    check.equal(2, resolutions)
    -- lint-allow: call-count #183 一次变化复制七组，随后稳定读取不再复制
    check.equal(14, copies)
  end)
  debug.sethook(previous, mask, count)
  check.is_true(ok, err)
end)

end)
