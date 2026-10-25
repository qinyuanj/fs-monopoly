require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local _config_reset = require("test.support.config_reset")


local function _assert_eq(a, b, msg)
  luassert.is.equal(b, a, msg)
end

local function _before()
  runtime_ports.reset_for_tests()
end

describe("TestRuntimePorts", function()

  before_each(function()
    _config_reset.reset_all()
  end)

  after_each(function()
    -- 本 spec 故意把 runtime 端口拆到未配置态验证空端口行为;拆完必须把共享端口基线
    -- 装回,否则 mutate 车道窄 suite 子集会撞空端口(#217)。
    support.restore_runtime_services()
  end)

  it("test_schedule_calls_fn_directly_when_no_scheduler_configured", function()
    _before()
    local called = false
    runtime_ports.schedule(0.1, function() called = true end)
    _assert_eq(called, true, "schedule should call fn directly when no scheduler port")
  end)

  it("test_schedule_delegates_to_configured_scheduler", function()
    _before()
    local received_delay, received_fn
    runtime_ports.configure({
      schedule = function(delay, fn)
        received_delay = delay
        received_fn = fn
      end,
    })
    local my_fn = function() end
    runtime_ports.schedule(0.5, my_fn)
    _assert_eq(received_delay, 0.5, "configured scheduler should receive delay")
    _assert_eq(received_fn, my_fn, "configured scheduler should receive fn")
    runtime_ports.reset_for_tests()
  end)

  it("test_resolve_role_returns_nil_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.resolve_role("role_1"), nil, "resolve_role should return nil when not configured")
  end)

  it("test_resolve_role_delegates_to_configured_resolver", function()
    _before()
    local got_id
    runtime_ports.configure({
      resolve_role = function(player_id)
        got_id = player_id
        return { id = player_id }
      end,
    })
    local result = runtime_ports.resolve_role("p1")
    _assert_eq(got_id, "p1", "configured resolver should receive player_id")
    _assert_eq(result.id, "p1", "resolve_role should return configured result")
    runtime_ports.reset_for_tests()
  end)

  it("test_resolve_roles_returns_empty_when_not_configured", function()
    _before()
    local roles = runtime_ports.resolve_roles()
    _assert_eq(type(roles), "table", "resolve_roles should return table when not configured")
    _assert_eq(#roles, 0, "resolve_roles should return empty table when not configured")
  end)

  it("test_resolve_roles_delegates_to_configured_resolver", function()
    _before()
    local all_roles = { { id = "r1" }, { id = "r2" } }
    runtime_ports.configure({
      resolve_roles = function() return all_roles end,
    })
    _assert_eq(runtime_ports.resolve_roles(), all_roles, "resolve_roles should return configured result")
    runtime_ports.reset_for_tests()
  end)

  it("test_mark_role_lose_returns_nil_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.mark_role_lose({ id = "r1" }), nil, "mark_role_lose should return nil when not configured")
  end)

  it("test_mark_role_lose_delegates_to_configured_marker", function()
    _before()
    local marked_role
    runtime_ports.configure({
      mark_role_lose = function(role) marked_role = role end,
    })
    local role = { id = "r2" }
    runtime_ports.mark_role_lose(role)
    _assert_eq(marked_role, role, "mark_role_lose should delegate to configured marker")
    runtime_ports.reset_for_tests()
  end)

  it("test_call_role_die_returns_false_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.call_role_die({ id = "r1" }), false,
      "call_role_die should return false when not configured")
  end)

  it("test_call_role_die_delegates_to_configured_caller", function()
    _before()
    local received_role
    runtime_ports.configure({
      call_role_die = function(role)
        received_role = role
        return true
      end,
    })
    local role = { id = "r2" }
    _assert_eq(runtime_ports.call_role_die(role), true,
      "call_role_die should delegate to the configured caller")
    _assert_eq(received_role, role, "call_role_die should pass the role")
    runtime_ports.reset_for_tests()
  end)

  it("test_role_model_ports_fail_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.set_role_model(1, 42), false, "set_role_model should fail when not configured")
    _assert_eq(runtime_ports.reset_role_model(1), false, "reset_role_model should fail when not configured")
  end)

  it("test_resolve_camera_helper_returns_nil_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.resolve_camera_helper(), nil, "resolve_camera_helper should return nil when not configured")
  end)

  it("test_resolve_camera_helper_delegates_to_configured_resolver", function()
    _before()
    local helper = { kind = "camera" }
    runtime_ports.configure({
      resolve_camera_helper = function() return helper end,
    })
    _assert_eq(runtime_ports.resolve_camera_helper(), helper, "resolve_camera_helper should return configured result")
    runtime_ports.reset_for_tests()
  end)

  it("test_emit_event_returns_false_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.emit_event("evt", {}), false, "emit_event should return false when not configured")
  end)

  it("test_emit_event_delegates_to_configured_emitter", function()
    _before()
    local received = {}
    runtime_ports.configure({
      emit_event = function(name, payload, opts)
        received.name = name
        received.payload = payload
        received.opts = opts
        return true
      end,
    })
    local payload = { data = 1 }
    local opts = { broadcast = true }
    local result = runtime_ports.emit_event("test_event", payload, opts)
    _assert_eq(result, true, "emit_event should return configured emitter result")
    _assert_eq(received.name, "test_event", "emit_event should pass event name")
    _assert_eq(received.payload, payload, "emit_event should pass payload")
    _assert_eq(received.opts, opts, "emit_event should pass opts")
    runtime_ports.reset_for_tests()
  end)

  it("test_wall_now_seconds_returns_zero_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.wall_now_seconds(), 0, "wall_now_seconds should return 0 when not configured")
  end)

  it("test_wall_now_seconds_delegates_to_configured_fn", function()
    _before()
    runtime_ports.configure({ wall_now_seconds = function() return 1234.5 end })
    _assert_eq(runtime_ports.wall_now_seconds(), 1234.5, "wall_now_seconds should return configured result")
    runtime_ports.reset_for_tests()
  end)

  it("test_wall_diff_seconds_returns_zero_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.wall_diff_seconds(100.0, 99.0), 0, "wall_diff_seconds should return 0 when not configured")
  end)

  it("test_wall_diff_seconds_delegates_to_configured_fn", function()
    _before()
    local got_t1, got_t2
    runtime_ports.configure({
      wall_diff_seconds = function(t1, t2)
        got_t1 = t1
        got_t2 = t2
        return t1 - t2
      end,
    })
    local result = runtime_ports.wall_diff_seconds(10.5, 10.0)
    _assert_eq(result, 0.5, "wall_diff_seconds should return configured result")
    _assert_eq(got_t1, 10.5, "wall_diff_seconds should pass t1")
    _assert_eq(got_t2, 10.0, "wall_diff_seconds should pass t2")
    runtime_ports.reset_for_tests()
  end)

  it("test_cpu_now_seconds_returns_zero_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.cpu_now_seconds(), 0, "cpu_now_seconds should return 0 when not configured")
  end)

  it("test_cpu_now_seconds_delegates_to_configured_fn", function()
    _before()
    runtime_ports.configure({ cpu_now_seconds = function() return 99.9 end })
    _assert_eq(runtime_ports.cpu_now_seconds(), 99.9, "cpu_now_seconds should return configured result")
    runtime_ports.reset_for_tests()
  end)

  it("test_cpu_diff_seconds_returns_zero_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.cpu_diff_seconds(5.0, 4.0), 0, "cpu_diff_seconds should return 0 when not configured")
  end)

  it("test_cpu_diff_seconds_delegates_to_configured_fn", function()
    _before()
    runtime_ports.configure({
      cpu_diff_seconds = function(t1, t2) return t1 - t2 end,
    })
    _assert_eq(runtime_ports.cpu_diff_seconds(3.0, 2.5), 0.5, "cpu_diff_seconds should return configured result")
    runtime_ports.reset_for_tests()
  end)

  it("test_is_effect_idle_returns_true_when_not_configured", function()
    _before()
    _assert_eq(runtime_ports.is_effect_idle(), true, "is_effect_idle should return true when not configured")
  end)

  it("test_is_effect_idle_delegates_to_configured_fn", function()
    _before()
    runtime_ports.configure({ is_effect_idle = function() return false end })
    _assert_eq(runtime_ports.is_effect_idle(), false, "is_effect_idle should return configured result")
    runtime_ports.reset_for_tests()
  end)

  -- ════════════════════════════════════════════════════════════════════════
  -- T16 mutation-pinning specs for runtime_ports.rng_next_int (L17/L19) and
  -- runtime_ports.wall_now_hms (L84-L89). Per [[reference_mutate4lua_test_corpus]]:
  -- closure via busted spec. Per [[feedback_mutation_spec_state_inline]]: state
  -- shape inline; nil vs explicit fields are the mutation contract.
  -- ════════════════════════════════════════════════════════════════════════

  it("test_rng_next_int_forwards_min_and_max_and_returns_configured_result_l17_l19", function()
    _before()
    local got_min, got_max
    runtime_ports.configure({
      rng_next_int = function(min, max)
        got_min = min
        got_max = max
        return 42
      end,
    })
    local result = runtime_ports.rng_next_int(1, 100)
    _assert_eq(got_min, 1, "rng_next_int must forward min")
    _assert_eq(got_max, 100, "rng_next_int must forward max")
    _assert_eq(result, 42, "rng_next_int must return configured fn result")
    runtime_ports.reset_for_tests()
  end)

  it("test_rng_next_int_asserts_when_port_not_configured", function()
    _before()
    local ok, err = pcall(function() runtime_ports.rng_next_int(1, 10) end)
    luassert.truthy(ok == false, "rng_next_int with unconfigured port must error")
    luassert.truthy(tostring(err):find("rng_next_int"), "error must mention rng_next_int; got: " .. tostring(err))
  end)

  it("test_wall_now_hms_returns_nil_when_port_not_configured_l85_type_check", function()
    _before()
    _assert_eq(runtime_ports.wall_now_hms(), nil,
      "wall_now_hms must return nil when port not configured")
  end)

  it("test_wall_now_hms_returns_the_configured_fns_string_result_l92_happy_path", function()
    _before()
    runtime_ports.configure({ wall_now_hms = function() return "12:34:56" end })
    _assert_eq(runtime_ports.wall_now_hms(), "12:34:56",
      "wall_now_hms must return the string from configured fn")
    runtime_ports.reset_for_tests()
  end)

  it("test_wall_now_hms_returns_nil_when_configured_fn_throws_l88_pcall_and_l89_not_ok", function()
    _before()
    runtime_ports.configure({
      wall_now_hms = function() error("simulated_clock_failure", 0) end,
    })
    _assert_eq(runtime_ports.wall_now_hms(), nil,
      "wall_now_hms must return nil when fn throws (pcall not-ok branch)")
    runtime_ports.reset_for_tests()
  end)

  it("test_wall_now_hms_returns_nil_when_fn_returns_non_string_l89_type_check", function()
    _before()
    runtime_ports.configure({ wall_now_hms = function() return 12345 end })
    _assert_eq(runtime_ports.wall_now_hms(), nil,
      "wall_now_hms must return nil when fn returns a number; got: " ..
      tostring(runtime_ports.wall_now_hms()))
    runtime_ports.reset_for_tests()
  end)

  it("test_wall_now_hms_returns_nil_when_fn_returns_empty_string_l89_hms_empty", function()
    _before()
    runtime_ports.configure({ wall_now_hms = function() return "" end })
    _assert_eq(runtime_ports.wall_now_hms(), nil,
      "wall_now_hms must reject empty-string result")
    runtime_ports.reset_for_tests()
  end)

  it("test_unconfigured_defaults_are_pinned", function()
    -- #293:默认值位点(false→true / 0→1)未被断言,补钉。
    runtime_ports.reset_for_tests()
    luassert.truthy(runtime_ports.archives_enabled() == false, "archives_enabled should default to false")
    luassert.truthy(runtime_ports.get_archive_int() == 0, "get_archive_int should default to 0")
    luassert.truthy(runtime_ports.set_archive_int() == false, "set_archive_int should default to false")
    luassert.truthy(runtime_ports.get_archive_str() == nil, "get_archive_str should default to nil (unreadable)")
    luassert.truthy(runtime_ports.set_archive_str() == false, "set_archive_str should default to false")
  end)


end)
