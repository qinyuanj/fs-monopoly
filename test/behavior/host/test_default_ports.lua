---@diagnostic disable: need-check-nil, different-requires, undefined-field

require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local function _assert_equal(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local default_ports = require("src.host.default_ports")

describe("TestDefaultPorts", function()

local function _test_end_game_routes_to_host_and_leaves_diagnostics()
  -- #609 审查收口:end_game 必须直调宿主 game_end;API 缺失与宿主抛错都要
  -- 留痕并返回 false,不得静默、不得上抛(上抛会沿事件回调跳过后续收尾)。
  local host_calls = 0
  local function _ports_with_game_api(game_api)
    return default_ports.build({ current = function()
      return { env = { GameAPI = game_api } }
    end })
  end

  local ports = _ports_with_game_api({
    game_end = function()
      host_calls = host_calls + 1
    end,
  })
  _assert_equal(ports.end_game(), true, "end_game should confirm a successful host call")
  _assert_equal(host_calls, 1, "end_game should reach the host exactly once")

  local logger = require("src.foundation.log")
  local original_warn = logger.warn
  local warns = {}
  logger.warn = function(...)
    warns[#warns + 1] = table.concat({ ... }, " ")
  end
  local ok_missing, missing_result = pcall(function()
    return _ports_with_game_api({}).end_game()
  end)
  local ok_raising, raising_result = pcall(function()
    return _ports_with_game_api({
      game_end = function()
        error("host exploded")
      end,
    }).end_game()
  end)
  logger.warn = original_warn

  _assert_equal(ok_missing and missing_result == false, true, "missing game_end should report false, not raise")
  _assert_equal(ok_raising and raising_result == false, true, "raising host game_end must be contained and report false")
  _assert_equal(#warns, 2, "missing and raising host game_end should each leave one warn")
end

local function _test_wall_diff_seconds_prefers_game_api_then_falls_back()
  local ctx = {
    env = {
      GameAPI = {
        get_timestamp_diff = function(current, previous)
          return (current - previous) * 2
        end,
      },
    },
  }
  local runtime_ctx = {
    current = function()
      return ctx
    end,
  }
  local ports = default_ports.build(runtime_ctx)

  _assert_equal(ports.wall_diff_seconds(9, 7), 4, "wall diff should prefer GameAPI semantics when available")
  ctx.env.GameAPI.get_timestamp_diff = nil
  _assert_equal(ports.wall_diff_seconds(9, 7), 2, "wall diff should fall back to arithmetic when GameAPI diff is unavailable")
  _assert_equal(ports.wall_diff_seconds("x", 7), 0, "wall diff should return 0 for non-numeric fallback inputs")
end

local function _test_cpu_now_seconds_prefers_game_api_then_falls_back()
  local ctx = { env = {} }
  local runtime_ctx = {
    current = function()
      return ctx
    end,
  }
  local ports = default_ports.build(runtime_ctx)

  local now = ports.cpu_now_seconds()
  luassert.is_number(now, "cpu_now should produce a number even without GameAPI")

  ctx.env.GameAPI = { get_timestamp = function() return 12345 end }
  _assert_equal(ports.cpu_now_seconds(), 12345, "cpu_now should prefer GameAPI timestamp when available")
end

local function _test_wall_now_hms_formats_from_game_api_parts()
  local ctx = {
    env = {
      GameAPI = {
        get_timestamp = function() return 1000 end,
        get_hour = function() return 10 end,
        get_minute = function() return 30 end,
        get_second = function() return 45 end,
      },
    },
  }
  local runtime_ctx = {
    current = function()
      return ctx
    end,
  }
  local ports = default_ports.build(runtime_ctx)

  _assert_equal(ports.wall_now_hms(), "10:30:45", "wall_now_hms should format from GameAPI parts")
  ctx.env.GameAPI.get_hour = nil
  _assert_equal(ports.wall_now_hms(), "", "missing part should yield empty string")
  ctx.env.GameAPI = nil
  _assert_equal(ports.wall_now_hms(), "", "no GameAPI should yield empty string")
end

local function _test_rng_next_int_routes_to_the_host_random_int_and_guards_its_inputs()
  local seen = nil
  local function _ports_with_game_api(game_api)
    return default_ports.build({ current = function()
      return { env = { GameAPI = game_api } }
    end })
  end

  local ports = _ports_with_game_api({
    random_int = function(min, max)
      seen = { min = min, max = max }
      return 5
    end,
  })

  _assert_equal(ports.rng_next_int(1, 10), 5, "rng_next_int should return the host random value")
  _assert_equal(seen.min, 1, "rng_next_int should pass the min bound through")
  _assert_equal(seen.max, 10, "rng_next_int should pass the max bound through")

  local ok_missing_min, err_missing_min = pcall(ports.rng_next_int, nil, 10)
  luassert.is_false(ok_missing_min, "rng_next_int should assert on a missing min bound")
  _assert_equal(string.find(tostring(err_missing_min), "rng.next_int requires min/max", 1, true) ~= nil, true,
    "missing-min error should carry the reason; got " .. tostring(err_missing_min))

  local ports_no_api = _ports_with_game_api({})
  local ok_no_api, err_no_api = pcall(ports_no_api.rng_next_int, 1, 10)
  luassert.is_false(ok_no_api, "rng_next_int should assert when the host lacks random_int")
  _assert_equal(string.find(tostring(err_no_api), "missing game api random_int", 1, true) ~= nil, true,
    "missing-api error should carry the reason; got " .. tostring(err_no_api))
end

local function _test_schedule_forwards_delay_and_callback_to_lua_api()
  local seen = nil
  local ctx = {
    env = {
      LuaAPI = {
        call_delay_time = function(delay, fn)
          seen = { delay = delay, fn = fn }
        end,
      },
    },
  }
  local ports = default_ports.build({ current = function() return ctx end })

  local called = false
  ports.schedule(nil, function()
    called = true
  end)
  _assert_equal(seen.delay, 0, "schedule should default a nil delay to 0")
  _assert_equal(called, false, "schedule should not invoke the callback synchronously when LuaAPI is present")

  seen = nil
  ports.schedule(3, function() end)
  _assert_equal(seen.delay, 3, "schedule should pass the explicit delay through")
end

local function _test_schedule_falls_back_to_sync_call_without_lua_api()
  local ctx = { env = {} }
  local ports = default_ports.build({ current = function() return ctx end })

  local called = false
  ports.schedule(1, function()
    called = true
  end)
  _assert_equal(called, true, "schedule should invoke the callback synchronously without LuaAPI")

  local ok, err = pcall(ports.schedule, 1, nil)
  _assert_equal(ok, false, "schedule should assert on a missing callback")
  _assert_equal(string.find(tostring(err), "schedule requires callback", 1, true) ~= nil, true,
    "missing-callback error should carry the reason; got " .. tostring(err))
end

local function _test_resolve_camera_helper_returns_context_helper_or_nil()
  local ports = default_ports.build({ current = function() return nil end })
  _assert_equal(ports.resolve_camera_helper(), nil, "no context should yield no camera helper")

  local ctx = { camera_helper = { kind = "cam" } }
  local ports_with_helper = default_ports.build({ current = function() return ctx end })
  _assert_equal(ports_with_helper.resolve_camera_helper().kind, "cam", "camera helper should come from the context")
end

local function _test_emit_event_delegates_to_the_host_trigger_and_reports_ok()
  local ctx = { env = {} }
  local ports = default_ports.build({ current = function() return ctx end })
  local support = require("test.support.shared_support")

  local received = nil
  local ok_result
  support.with_patches({
    {
      target = _G,
      key = "TriggerCustomEvent",
      value = function(event_name, payload)
        received = { event_name = event_name, payload = payload }
        return true
      end,
    },
  }, function()
    ok_result = ports.emit_event("my.event", { k = 1 })
  end)
  _assert_equal(ok_result, true, "emit_event should report success when the host trigger succeeds")
  _assert_equal(received.event_name, "my.event", "emit_event should pass the event name through")
  _assert_equal(received.payload.k, 1, "emit_event should pass the payload through")

  local raised_result
  support.with_patches({
    {
      target = _G,
      key = "TriggerCustomEvent",
      value = function()
        error("host trigger raised")
      end,
    },
  }, function()
    raised_result = ports.emit_event("my.event", {})
  end)
  _assert_equal(raised_result, false, "emit_event should return false when the host trigger raises")

  local missing_result
  support.with_patches({
    {
      target = _G,
      key = "TriggerCustomEvent",
      value = nil,
    },
  }, function()
    missing_result = ports.emit_event("my.event", {})
  end)
  _assert_equal(missing_result, false, "emit_event should return false without the host trigger")
end

local function _test_resolve_roles_returns_cached_when_populated()
  local ctx = {
    env = {
      GameAPI = {
        get_all_valid_roles = function()
          return { { id = 9 } }
        end,
      },
    },
    roles = { { id = 1 } },
  }
  local ports = default_ports.build({ current = function() return ctx end })

  local roles = ports.resolve_roles()

  _assert_equal(#roles, 1, "populated roles should come back as cached")
  _assert_equal(roles[1].id, 1, "populated roles should not be replaced by a host query")
end

local function _test_is_synthetic_player_answers_from_registry_and_defaults_false()
  -- #611:终局面板路由据此静默跳过合成 AI。判定来自合成角色注册表登记的
  -- player_id 集合(退役不擦除),注册表缺位时一律返回 false。
  local ctx = {
    synthetic_actor_registry = {
      is_synthetic_player = function(player_id)
        return player_id == -2
      end,
    },
  }
  local ports = default_ports.build({ current = function() return ctx end })

  _assert_equal(ports.is_synthetic_player(-2), true, "registered synthetic player should be reported")
  _assert_equal(ports.is_synthetic_player(1), false, "host player should not be reported as synthetic")

  local bare = default_ports.build({ current = function() return { roles = {} } end })
  _assert_equal(bare.is_synthetic_player(-2), false, "missing registry should yield false, not nil")
end

local function _test_resolve_role_returns_nil_without_game_api()
  local ctx = { roles = {} }
  local ports = default_ports.build({ current = function() return ctx end })

  _assert_equal(ports.resolve_role(1), nil, "no GameAPI should yield no resolved role (no error)")
  _assert_equal(#ports.resolve_roles(), 0, "no GameAPI should yield an empty role list (no error)")
end

local function _test_resolve_roles_refreshes_empty_roles_from_game_api()
  local ctx = {
    env = {
      GameAPI = {
        get_all_valid_roles = function()
          return { { id = 1 }, { id = 2 } }
        end,
      },
    },
    roles = {},
  }
  local ports = default_ports.build({ current = function() return ctx end })

  local roles = ports.resolve_roles()

  _assert_equal(#roles, 2, "resolve_roles should fall back to the host role query")
  _assert_equal(roles[1].id, 1, "resolve_roles should return the queried roles")
  _assert_equal(ctx.roles[1].id, 1, "resolve_roles should cache the queried roles back onto the context")
end

local function _test_resolve_roles_queries_game_api_when_roles_not_initialized()
  local ctx = {
    env = {
      GameAPI = {
        get_all_valid_roles = function()
          return { { id = 7 } }
        end,
      },
    },
  }
  local ports = default_ports.build({ current = function() return ctx end })

  local roles = ports.resolve_roles()

  _assert_equal(#roles, 1, "resolve_roles should query the host when ctx.roles is not a table")
  _assert_equal(roles[1].id, 7, "resolve_roles should return the queried role")
end

local function _test_is_effect_idle_reports_the_effect_track_state()
  local ctx = { env = {} }
  local ports = default_ports.build({ current = function() return ctx end })
  local support = require("test.support.shared_support")
  local effect_track = require("src.ui.render.support.effect_track")

  local idle_result
  support.with_patches({
    {
      target = effect_track,
      key = "is_idle",
      value = function()
        return false
      end,
    },
  }, function()
    idle_result = ports.is_effect_idle()
  end)
  _assert_equal(idle_result, false, "is_effect_idle should delegate to the effect track's idle state")
end

-- effect_track 是 UI 层可选依赖，探测壳的三条异常臂各自定型：
-- require 抛错 / 返回非表 / 表上缺 is_idle 都必须回落「视为空闲」true。
local function _with_effect_track_module(value, fn)
  local support = require("test.support.shared_support")
  support.with_patches({
    { target = package.loaded, key = "src.ui.render.support.effect_track", value = nil },
    { target = package.preload, key = "src.ui.render.support.effect_track", value = value },
  }, fn)
end

local function _test_is_effect_idle_falls_back_to_true_when_require_raises()
  local ports = default_ports.build({ current = function() return nil end })
  local result
  _with_effect_track_module(function()
    error("effect track unavailable")
  end, function()
    result = ports.is_effect_idle()
  end)
  _assert_equal(result, true, "is_effect_idle should treat an unloadable effect track as idle")
end

local function _test_is_effect_idle_falls_back_to_true_when_module_is_not_a_table()
  local ports = default_ports.build({ current = function() return nil end })
  local result
  _with_effect_track_module(function()
    return 42
  end, function()
    result = ports.is_effect_idle()
  end)
  _assert_equal(result, true, "is_effect_idle should treat a non-table effect track as idle")
end

local function _test_is_effect_idle_falls_back_to_true_when_is_idle_is_missing()
  local ports = default_ports.build({ current = function() return nil end })
  local result
  _with_effect_track_module(function()
    return {}
  end, function()
    result = ports.is_effect_idle()
  end)
  _assert_equal(result, true, "is_effect_idle should treat a missing is_idle probe as idle")
end

describe("TestDefaultPortsCustomArchiveAccess", function()
  local original_enums
  before_each(function()
    original_enums = _G.Enums
    _G.Enums = { ArchiveType = { Int = 4 } }
  end)
  after_each(function()
    _G.Enums = original_enums
  end)

local function _ports_with_role(role, game_api)
  local ctx = { env = { GameAPI = game_api }, roles = role and { role } or {} }
  return default_ports.build({ current = function() return ctx end })
end

local function _test_archives_enabled_reflects_game_api_then_defaults_false()
  local ports = _ports_with_role(nil, { is_archives_enabled = function() return true end })
  _assert_equal(ports.archives_enabled(), true, "archives_enabled should follow GameAPI when present")

  local ports_off = _ports_with_role(nil, {})
  _assert_equal(ports_off.archives_enabled(), false, "archives_enabled should default to false without GameAPI support")

  local ports_no_api = _ports_with_role(nil, nil)
  _assert_equal(ports_no_api.archives_enabled(), false, "archives_enabled should be false (not error) when GameAPI is absent")
end

local function _test_get_archive_int_defaults_to_zero_for_non_numeric_archive()
  local role = {
    get_roleid = function() return 9 end,
    get_archive_by_type = function() return "not-a-number" end,
  }
  local ports = _ports_with_role(role, {})

  _assert_equal(ports.get_archive_int(9, 1001), 0, "non-numeric archive value should default to 0")
end

local function _test_get_archive_int_reads_int_archive_from_resolved_role()
  local seen = {}
  local role = {
    get_roleid = function() return 9 end,
    get_archive_by_type = function(archive_type, key)
      seen[#seen + 1] = { archive_type = archive_type, key = key }
      return 42
    end,
  }
  local ports = _ports_with_role(role, {})

  _assert_equal(ports.get_archive_int(9, 1001), 42, "get_archive_int should return the role's stored value")
  _assert_equal(seen[1].archive_type, 4, "get_archive_int should request the Int archive type")
  _assert_equal(seen[1].key, 1001, "get_archive_int should pass the archive key through")
  _assert_equal(ports.get_archive_int(404, 1001), 0, "get_archive_int should default to 0 for an unresolved role")
end

local function _test_set_archive_int_writes_int_archive_on_resolved_role()
  local written = nil
  local role = {
    get_roleid = function() return 9 end,
    set_archive_by_type = function(archive_type, key, value)
      written = { archive_type = archive_type, key = key, value = value }
      return true
    end,
  }
  local ports = _ports_with_role(role, {})

  _assert_equal(ports.set_archive_int(9, 1002, 80000), true, "set_archive_int should report success")
  _assert_equal(written.archive_type, 4, "set_archive_int should target the Int archive type")
  _assert_equal(written.key, 1002, "set_archive_int should pass the archive key")
  _assert_equal(written.value, 80000, "set_archive_int should pass the new value")
  _assert_equal(ports.set_archive_int(404, 1002, 1), false, "set_archive_int should fail safely for an unresolved role")
end

it("test_archives_enabled_reflects_game_api_then_defaults_false", _test_archives_enabled_reflects_game_api_then_defaults_false)
it("test_get_archive_int_defaults_to_zero_for_non_numeric_archive", _test_get_archive_int_defaults_to_zero_for_non_numeric_archive)
it("test_get_archive_int_reads_int_archive_from_resolved_role", _test_get_archive_int_reads_int_archive_from_resolved_role)
it("test_set_archive_int_writes_int_archive_on_resolved_role", _test_set_archive_int_writes_int_archive_on_resolved_role)
end)

-- #198 / ADR 0075:礼包码兑换记录存一个 Str 玩家存档 key。读不到时返回 nil
-- (区别于「从未写过」的空串),写不成返回 false;每条降级路径都要留 warn。
describe("TestDefaultPortsStrArchiveAccess", function()
  local STR = 5
  local original_enums
  local logger = require("src.foundation.log")
  local original_warn
  local warns

  before_each(function()
    original_enums = _G.Enums
    _G.Enums = { ArchiveType = { Int = 4, Str = STR } }
    original_warn = logger.warn
    warns = {}
    logger.warn = function(...)
      warns[#warns + 1] = table.concat({ ... }, " ")
    end
  end)
  after_each(function()
    _G.Enums = original_enums
    logger.warn = original_warn
  end)

  local function _ports_with(role)
    local ctx = { env = { GameAPI = {} }, roles = role and { role } or {} }
    return default_ports.build({ current = function() return ctx end })
  end

  local function _role(fields)
    fields.get_roleid = function() return 9 end
    return fields
  end

  it("test_get_archive_str_reads_str_archive_from_resolved_role", function()
    local seen = {}
    local ports = _ports_with(_role({
      get_archive_by_type = function(archive_type, key)
        seen[#seen + 1] = { archive_type = archive_type, key = key }
        return "3,7"
      end,
    }))

    _assert_equal(ports.get_archive_str(9, 1056), "3,7", "get_archive_str should return the stored string")
    _assert_equal(seen[1].archive_type, STR, "get_archive_str should request the Str archive type")
    _assert_equal(seen[1].key, 1056, "get_archive_str should pass the key through")
  end)

  it("test_set_archive_str_writes_str_archive_on_resolved_role", function()
    local written
    local ports = _ports_with(_role({
      set_archive_by_type = function(archive_type, key, value)
        written = { archive_type = archive_type, key = key, value = value }
      end,
    }))

    _assert_equal(ports.set_archive_str(9, 1056, "3,7"), true, "set_archive_str should report a completed host call")
    _assert_equal(written.archive_type, STR, "set_archive_str should target the Str archive type")
    _assert_equal(written.key, 1056, "set_archive_str should pass the key")
    _assert_equal(written.value, "3,7", "set_archive_str should pass the value")
  end)

  it("test_str_archive_degrades_when_type_enum_is_missing", function()
    _G.Enums = { ArchiveType = { Int = 4 } }
    local ports = _ports_with(_role({
      get_archive_by_type = function() return "3" end,
      set_archive_by_type = function() end,
    }))

    _assert_equal(ports.get_archive_str(9, 1056), nil, "read without Str enum should degrade to nil")
    _assert_equal(ports.set_archive_str(9, 1056, "3"), false, "write without Str enum should report failure")
    _assert_equal(#warns, 2, "each degraded call should leave a warn")
  end)

  it("test_str_archive_degrades_when_host_methods_are_missing", function()
    local ports = _ports_with(_role({}))

    _assert_equal(ports.get_archive_str(9, 1056), nil, "read without host method should degrade to nil")
    _assert_equal(ports.set_archive_str(9, 1056, "3"), false, "write without host method should report failure")
    _assert_equal(ports.get_archive_str(404, 1056), nil, "unresolved role should degrade to nil")
    _assert_equal(#warns, 3, "each degraded call should leave a warn")
  end)

  it("test_str_archive_degrades_when_host_raises", function()
    local ports = _ports_with(_role({
      get_archive_by_type = function() error("host read exploded") end,
      set_archive_by_type = function() error("host write exploded") end,
    }))

    _assert_equal(ports.get_archive_str(9, 1056), nil, "raising host read should degrade to nil")
    _assert_equal(ports.set_archive_str(9, 1056, "3"), false, "raising host write should report failure")
    _assert_equal(#warns, 2, "each raising call should leave a warn")
    _assert_equal(warns[1]:find("host read exploded", 1, true) ~= nil, true, "warn should carry the host error")
  end)

  it("test_get_archive_str_degrades_for_non_string_value", function()
    local ports = _ports_with(_role({
      get_archive_by_type = function() return 12 end,
    }))

    _assert_equal(ports.get_archive_str(9, 1056), nil, "non-string archive value should degrade to nil")
  end)
end)

-- ═══════════════════════════════════════════════════════════════════════
-- #334 / ADR 0046:mark_role_lose 保留 role.lose() 不换方法,跳过分支必留痕;
-- call_role_die 默认接线到 role_die 宿主适配(ADR 0046)。
-- ═══════════════════════════════════════════════════════════════════════

local function _test_mark_role_lose_calls_lose_on_the_role()
  local ctx = { env = {} }
  local runtime_ctx = {
    current = function()
      return ctx
    end,
  }
  local ports = default_ports.build(runtime_ctx)

  local marked = 0
  local role = {
    lose = function()
      marked = marked + 1
    end,
  }
  ports.mark_role_lose(role)
  _assert_equal(marked, 1, "mark_role_lose should call role.lose once (#334 keeps the marker method)")
end

local function _test_mark_role_lose_warns_when_role_is_nil()
  local ctx = { env = {} }
  local runtime_ctx = {
    current = function()
      return ctx
    end,
  }
  local ports = default_ports.build(runtime_ctx)

  local warns = {}
  local support = require("test.support.shared_support")
  support.with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    ports.mark_role_lose(nil)
  end)
  _assert_equal(#warns, 1, "nil role must leave exactly one warn (ADR 0046)")
  _assert_equal(string.find(warns[1], "role is nil", 1, true) ~= nil, true,
    "nil role warn should carry the skip reason; got " .. tostring(warns[1]))
end

local function _test_mark_role_lose_warns_when_role_lacks_lose()
  local ctx = { env = {} }
  local runtime_ctx = {
    current = function()
      return ctx
    end,
  }
  local ports = default_ports.build(runtime_ctx)

  local warns = {}
  local support = require("test.support.shared_support")
  support.with_patches({
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    ports.mark_role_lose({ id = 1 })
  end)
  _assert_equal(#warns, 1, "a role without lose must leave exactly one warn (ADR 0046)")
  _assert_equal(string.find(warns[1], "lacks lose", 1, true) ~= nil, true,
    "missing-lose warn should carry the skip reason; got " .. tostring(warns[1]))
end

local function _test_call_role_die_default_is_wired_to_the_host_adapter()
  local ctx = { env = {} }
  local runtime_ctx = {
    current = function()
      return ctx
    end,
  }
  local ports = default_ports.build(runtime_ctx)

  local role = {
    die = function(_, arg)
      return arg == nil
    end,
  }
  _assert_equal(ports.call_role_die(role), true,
    "call_role_die should default to the single-signature host adapter (ADR 0046)")
  _assert_equal(ports.call_role_die({}), false,
    "a role without die should fail through the adapter")
end


it("test_end_game_routes_to_host_and_leaves_diagnostics", _test_end_game_routes_to_host_and_leaves_diagnostics)
it("test_wall_diff_seconds_prefers_game_api_then_falls_back", _test_wall_diff_seconds_prefers_game_api_then_falls_back)
it("test_cpu_now_seconds_prefers_game_api_then_falls_back", _test_cpu_now_seconds_prefers_game_api_then_falls_back)
it("test_wall_now_hms_formats_from_game_api_parts", _test_wall_now_hms_formats_from_game_api_parts)
it("test_rng_next_int_routes_to_the_host_random_int_and_guards_its_inputs", _test_rng_next_int_routes_to_the_host_random_int_and_guards_its_inputs)
it("test_schedule_forwards_delay_and_callback_to_lua_api", _test_schedule_forwards_delay_and_callback_to_lua_api)
it("test_schedule_falls_back_to_sync_call_without_lua_api", _test_schedule_falls_back_to_sync_call_without_lua_api)
it("test_resolve_camera_helper_returns_context_helper_or_nil", _test_resolve_camera_helper_returns_context_helper_or_nil)
it("test_emit_event_delegates_to_the_host_trigger_and_reports_ok", _test_emit_event_delegates_to_the_host_trigger_and_reports_ok)
it("test_resolve_roles_returns_cached_when_populated", _test_resolve_roles_returns_cached_when_populated)
it("test_is_synthetic_player_answers_from_registry_and_defaults_false", _test_is_synthetic_player_answers_from_registry_and_defaults_false)
it("test_resolve_role_returns_nil_without_game_api", _test_resolve_role_returns_nil_without_game_api)
it("test_resolve_roles_refreshes_empty_roles_from_game_api", _test_resolve_roles_refreshes_empty_roles_from_game_api)
it("test_resolve_roles_queries_game_api_when_roles_not_initialized", _test_resolve_roles_queries_game_api_when_roles_not_initialized)
it("test_is_effect_idle_reports_the_effect_track_state", _test_is_effect_idle_reports_the_effect_track_state)
it("test_is_effect_idle_falls_back_to_true_when_require_raises", _test_is_effect_idle_falls_back_to_true_when_require_raises)
it("test_is_effect_idle_falls_back_to_true_when_module_is_not_a_table", _test_is_effect_idle_falls_back_to_true_when_module_is_not_a_table)
it("test_is_effect_idle_falls_back_to_true_when_is_idle_is_missing", _test_is_effect_idle_falls_back_to_true_when_is_idle_is_missing)
it("test_mark_role_lose_calls_lose_on_the_role", _test_mark_role_lose_calls_lose_on_the_role)
it("test_mark_role_lose_warns_when_role_is_nil", _test_mark_role_lose_warns_when_role_is_nil)
it("test_mark_role_lose_warns_when_role_lacks_lose", _test_mark_role_lose_warns_when_role_lacks_lose)
it("test_call_role_die_default_is_wired_to_the_host_adapter", _test_call_role_die_default_is_wired_to_the_host_adapter)
end)
