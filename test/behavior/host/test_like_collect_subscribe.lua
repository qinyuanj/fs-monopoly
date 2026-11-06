require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local with_patches = support.with_patches

-- 与 src/host/like_collect_subscribe.lua 的编辑器配置为真源：事件名逐字不可漂移。
-- 这里重复字面量是有意的——src 侧漂移时行为测试即红。
local LIKE_EVENT = "evt_click_like"
local COLLECT_EVENT = "evt_add_collection"
local SUBSCRIBE_EVENT = "evt_subscribe"
local SUBSCRIBE_CLICK_EVENT = "evt_not_subscribe"
local SUBSCRIBE_TIPS_TEXT = "点击\"更多\"完成订阅，下次登录领取订阅任务奖励。"

local function _game()
  return {}
end

local function _role(overrides)
  local role = {
    show_like_panel = function() end,
    get_ctrl_unit = function() return "unit_1" end,
    is_subscribed_map_author = function() return false end,
  }
  for key, value in pairs(overrides or {}) do
    role[key] = value
  end
  return role
end

local function _with_env(opts, fn)
  opts = opts or {}
  local env = {
    registrations = {},
    unit_sends = {},
    panel_calls = {},
    tips_calls = {},
    scheduled = {},
    warnings = {},
  }
  local role = opts.role or _role()

  local function _register_trigger(args, callback)
    env.registrations[#env.registrations + 1] = { args = args, callback = callback }
  end

  local patches = {
    {
      key = "EVENT",
      value = { UI_CUSTOM_EVENT = "UI_CUSTOM_EVENT" },
    },
    {
      key = "RegisterTriggerEvent",
      value = opts.register_trigger or _register_trigger,
    },
    {
      key = "LuaAPI",
      value = {
        unit_send_custom_event = function(unit, event_name, payload)
          env.unit_sends[#env.unit_sends + 1] = {
            unit = unit,
            event_name = event_name,
            payload = payload,
          }
        end,
      },
    },
    {
      key = "GameAPI",
      value = opts.game_api or {
        get_all_valid_roles = function() return { role } end,
      },
    },
    {
      key = "GlobalAPI",
      value = {
        show_tips = function(text, duration)
          env.tips_calls[#env.tips_calls + 1] = { text = text, duration = duration }
        end,
      },
    },
    {
      key = "SetTimeOut",
      value = function(delay, callback)
        env.scheduled[#env.scheduled + 1] = { delay = delay, callback = callback }
        return true
      end,
    },
    {
      target = require("src.foundation.log"),
      key = "warn",
      value = function(...)
        env.warnings[#env.warnings + 1] = table.concat({ ... }, " ")
      end,
    },
  }

  with_patches(patches, function()
    local module = require("src.host.like_collect_subscribe")
    fn(module, env, role)
  end)
end

local function _find_callback(env, event_name)
  for _, reg in ipairs(env.registrations) do
    if reg.args[2] == event_name then
      return reg.callback
    end
  end
  return nil
end

describe("TestLikeCollectSubscribe", function()

local function _test_setup_registers_three_listeners_once()
  _with_env({}, function(module, env, _)
    local game = _game()
    module.setup(game)

    _assert_eq(#env.registrations, 3, "should register three listeners")
    _assert_eq(env.registrations[1].args[1], "UI_CUSTOM_EVENT", "first listener kind")
    _assert_eq(env.registrations[1].args[2], LIKE_EVENT, "first listener event name")
    _assert_eq(env.registrations[2].args[2], COLLECT_EVENT, "second listener event name")
    _assert_eq(env.registrations[3].args[2], SUBSCRIBE_CLICK_EVENT, "third listener event name")

    local rt = module._runtime(game)
    _assert_eq(rt.setup_done, true, "runtime should mark setup done")

    module.setup(game)
    _assert_eq(#env.registrations, 3, "repeated setup should not register again")
  end)
end

local function _test_setup_skips_registration_without_host_contract()
  _with_env({
    register_trigger = function() error("should not be called") end,
  }, function(module, env, _)
    -- EVENT contract missing
    with_patches({
      { key = "EVENT", value = nil },
      {
        target = require("src.foundation.log"),
        key = "warn",
        value = function(...)
          env.warnings[#env.warnings + 1] = table.concat({ ... }, " ")
        end,
      },
    }, function()
      module.setup(_game())
    end)

    luassert.truthy(
      #env.warnings > 0 and env.warnings[1]:find("host event contract missing", 1, true),
      "should warn when host event contract is missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_like_click_opens_panel_and_sends_event()
  _with_env({}, function(module, env, role)
    local game = _game()
    module.setup(game)

    role.show_like_panel = function()
      env.panel_calls[#env.panel_calls + 1] = true
    end

    local callback = _find_callback(env, LIKE_EVENT)
    luassert.is_not_nil(callback, "like listener should be registered")
    callback(nil, nil, { role = role })

    _assert_eq(#env.panel_calls, 1, "panel should be opened once")
    _assert_eq(#env.unit_sends, 1, "unit event should be sent once")
    _assert_eq(env.unit_sends[1].unit, "unit_1", "unit should come from role")
    _assert_eq(env.unit_sends[1].event_name, LIKE_EVENT, "event name should be like")
    _assert_eq(type(env.unit_sends[1].payload), "table", "payload should be a table")
  end)
end

local function _test_collect_click_opens_panel_and_sends_event()
  _with_env({}, function(module, env, role)
    local game = _game()
    module.setup(game)

    role.show_like_panel = function()
      env.panel_calls[#env.panel_calls + 1] = true
    end

    local callback = _find_callback(env, COLLECT_EVENT)
    luassert.is_not_nil(callback, "collect listener should be registered")
    callback(nil, nil, { role = role })

    _assert_eq(#env.panel_calls, 1, "panel should be opened once")
    _assert_eq(#env.unit_sends, 1, "unit event should be sent once")
    _assert_eq(env.unit_sends[1].event_name, COLLECT_EVENT, "event name should be collect")
  end)
end

local function _test_subscribe_click_opens_panel_and_shows_tips()
  _with_env({}, function(module, env, role)
    local game = _game()
    module.setup(game)

    role.show_like_panel = function()
      env.panel_calls[#env.panel_calls + 1] = true
    end

    local callback = _find_callback(env, SUBSCRIBE_CLICK_EVENT)
    luassert.is_not_nil(callback, "subscribe listener should be registered")
    callback(nil, nil, { role = role })

    _assert_eq(#env.panel_calls, 1, "panel should be opened once")
    _assert_eq(#env.unit_sends, 0, "subscribe click should not send unit event")
    _assert_eq(#env.tips_calls, 1, "tips should be shown once")
    _assert_eq(env.tips_calls[1].text, SUBSCRIBE_TIPS_TEXT, "tips text should match")
    _assert_eq(env.tips_calls[1].duration, 3.0, "tips duration should be 3.0")
  end)
end

local function _test_map_enter_check_uses_zero_point_one_delay()
  _with_env({}, function(module, env, _)
    module.setup(_game())

    _assert_eq(#env.scheduled, 1, "should schedule one delayed check")
    _assert_eq(env.scheduled[1].delay, 0.1, "delay should be 0.1 seconds")
  end)
end

local function _test_map_enter_subscribed_sends_subscribe_event()
  _with_env({
    role = _role({ is_subscribed_map_author = function() return true end }),
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    env.scheduled[1].callback()

    _assert_eq(#env.unit_sends, 1, "should send one unit event")
    _assert_eq(env.unit_sends[1].event_name, SUBSCRIBE_EVENT, "should send subscribe event")

    local rt = module._runtime(game)
    _assert_eq(rt.subscribe_sent, true, "should mark subscribe sent")
  end)
end

local function _test_map_enter_not_subscribed_sends_nothing()
  _with_env({
    role = _role({ is_subscribed_map_author = function() return false end }),
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    env.scheduled[1].callback()

    _assert_eq(#env.unit_sends, 0, "not subscribed should not send any unit event")
  end)
end

local function _test_subscription_event_not_sent_twice()
  _with_env({
    role = _role({ is_subscribed_map_author = function() return true end }),
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    env.scheduled[1].callback()
    _assert_eq(#env.unit_sends, 1, "first check should send one event")

    env.scheduled[1].callback()
    _assert_eq(#env.unit_sends, 1, "second check should not duplicate")

    module.setup(game)
    module._check_subscription(game)
    _assert_eq(#env.unit_sends, 1, "setup re-run should not duplicate")
  end)
end

local function _test_subscription_send_failure_is_not_latched_and_retries()
  local send_should_fail = true
  _with_env({
    role = _role({ is_subscribed_map_author = function() return true end }),
  }, function(module, env, _)
    local game = _game()
    with_patches({
      {
        key = "LuaAPI",
        value = {
          unit_send_custom_event = function(unit, event_name, payload)
            if send_should_fail then
              error("send boom")
            end
            env.unit_sends[#env.unit_sends + 1] = {
              unit = unit,
              event_name = event_name,
              payload = payload,
            }
          end,
        },
      },
    }, function()
      module.setup(game)
      env.scheduled[1].callback()
      local rt = module._runtime(game)
      _assert_eq(#env.unit_sends, 0, "failed send should not deliver")
      _assert_eq(rt.subscribe_sent, false, "failed send must not latch")

      send_should_fail = false
      module._check_subscription(game)
      _assert_eq(#env.unit_sends, 1, "next check should retry the send")
      _assert_eq(env.unit_sends[1].event_name, SUBSCRIBE_EVENT, "retry should send subscribe event")
      _assert_eq(rt.subscribe_sent, true, "successful retry should latch")
    end)
  end)
end

-- 「unit 缺失 / LuaAPI 缺失」与宿主抛错同属瞬时失败:都不得锁存,下次检测要重发。
local function _test_subscription_missing_ctrl_unit_is_not_latched_and_retries()
  local unit = nil
  _with_env({
    role = _role({
      is_subscribed_map_author = function() return true end,
      get_ctrl_unit = function() return unit end,
    }),
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    env.scheduled[1].callback()
    _assert_eq(#env.unit_sends, 0, "no ctrl unit should deliver nothing")

    unit = "unit_late"
    module._check_subscription(game)
    _assert_eq(#env.unit_sends, 1, "next check should retry once the ctrl unit exists")
    _assert_eq(env.unit_sends[1].unit, "unit_late", "retry should target the late ctrl unit")
  end)
end

local function _test_subscription_missing_lua_api_is_not_latched_and_retries()
  _with_env({
    role = _role({ is_subscribed_map_author = function() return true end }),
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    with_patches({ { key = "LuaAPI", value = nil } }, function()
      env.scheduled[1].callback()
    end)
    _assert_eq(#env.unit_sends, 0, "missing LuaAPI should deliver nothing")

    module._check_subscription(game)
    _assert_eq(#env.unit_sends, 1, "next check should retry once LuaAPI is back")
    _assert_eq(env.unit_sends[1].event_name, SUBSCRIBE_EVENT, "retry should send subscribe event")
  end)
end

local function _test_like_click_without_role_warns_only()
  _with_env({}, function(module, env, _)
    module.setup(_game())
    local callback = _find_callback(env, LIKE_EVENT)

    local ok, err = pcall(callback, nil, nil, {})

    _assert_eq(ok, true, "a like click without role should not raise: " .. tostring(err))
    _assert_eq(#env.unit_sends, 0, "a like click without role should send nothing")
    luassert.truthy(
      env.warnings[1] ~= nil and env.warnings[1]:find("show_like_panel missing", 1, true) ~= nil,
      "should mention show_like_panel missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_host_call_failures_warn_only()
  _with_env({
    role = _role({
      show_like_panel = function() error("panel boom") end,
      is_subscribed_map_author = function() error("subscribe boom") end,
    }),
    game_api = {
      get_all_valid_roles = function() return { _role({ is_subscribed_map_author = function() error("subscribe boom") end }) } end,
    },
  }, function(module, env, _)
    local game = _game()
    module.setup(game)

    local like_callback = _find_callback(env, LIKE_EVENT)
    like_callback(nil, nil, { role = _role({ show_like_panel = function() error("panel boom") end }) })

    env.scheduled[1].callback()

    luassert.truthy(#env.warnings > 0, "should log warnings for host failures")
  end)
end

local function _test_unit_send_failure_warns_only()
  _with_env({
    role = _role(),
  }, function(module, env, _)
    local game = _game()
    with_patches({
      {
        key = "LuaAPI",
        value = {
          unit_send_custom_event = function() error("send boom") end,
        },
      },
    }, function()
      module.setup(game)
      local like_callback = _find_callback(env, LIKE_EVENT)
      like_callback(nil, nil, { role = _role() })
    end)

    luassert.truthy(#env.warnings > 0, "should warn when unit send fails")
  end)
end

local function _test_unit_send_missing_ctrl_unit_warns()
  _with_env({}, function(module, env, _)
    local game = _game()
    module.setup(game)
    local like_callback = _find_callback(env, LIKE_EVENT)
    like_callback(nil, nil, { role = { show_like_panel = function() end } })

    luassert.truthy(#env.warnings > 0, "should warn when role has no get_ctrl_unit")
    luassert.truthy(
      env.warnings[1]:find("unit missing", 1, true) ~= nil,
      "should mention unit missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_unit_send_ctrl_unit_call_failure_warns()
  _with_env({}, function(module, env, _)
    local game = _game()
    module.setup(game)
    local like_callback = _find_callback(env, LIKE_EVENT)
    like_callback(nil, nil, {
      role = _role({ get_ctrl_unit = function() error("ctrl boom") end }),
    })

    luassert.truthy(#env.warnings > 0, "should warn when get_ctrl_unit raises")
    luassert.truthy(
      env.warnings[1]:find("unit missing", 1, true) ~= nil,
      "should mention unit missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_unit_send_ctrl_unit_returns_nil_warns()
  _with_env({}, function(module, env, _)
    local game = _game()
    module.setup(game)
    local like_callback = _find_callback(env, LIKE_EVENT)
    like_callback(nil, nil, { role = _role({ get_ctrl_unit = function() return nil end }) })

    luassert.truthy(#env.warnings > 0, "should warn when get_ctrl_unit returns nil")
    luassert.truthy(
      env.warnings[1]:find("unit missing", 1, true) ~= nil,
      "should mention unit missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_unit_send_missing_lua_api_warns()
  _with_env({}, function(module, env, _)
    local game = _game()
    module.setup(game)
    with_patches({
      { key = "LuaAPI", value = nil },
    }, function()
      local like_callback = _find_callback(env, LIKE_EVENT)
      like_callback(nil, nil, { role = _role() })
    end)

    luassert.truthy(#env.warnings > 0, "should warn when LuaAPI is missing")
    luassert.truthy(
      env.warnings[1]:find("LuaAPI missing", 1, true) ~= nil,
      "should mention LuaAPI missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_show_tips_missing_global_api_warns()
  _with_env({}, function(module, env, _)
    local game = _game()
    module.setup(game)
    with_patches({
      { key = "GlobalAPI", value = nil },
    }, function()
      local subscribe_callback = _find_callback(env, SUBSCRIBE_CLICK_EVENT)
      subscribe_callback(nil, nil, { role = _role() })
    end)

    luassert.truthy(#env.warnings > 0, "should warn when GlobalAPI is missing")
    luassert.truthy(
      env.warnings[1]:find("GlobalAPI.show_tips missing", 1, true) ~= nil,
      "should mention show_tips missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_show_tips_failure_warns_only()
  _with_env({}, function(module, env, _)
    local game = _game()
    module.setup(game)
    with_patches({
      {
        key = "GlobalAPI",
        value = {
          show_tips = function() error("tips boom") end,
        },
      },
    }, function()
      local subscribe_callback = _find_callback(env, SUBSCRIBE_CLICK_EVENT)
      subscribe_callback(nil, nil, { role = _role() })
    end)

    luassert.truthy(#env.warnings > 0, "should warn when show_tips raises")
  end)
end

local function _test_subscription_check_without_valid_role_warns()
  _with_env({
    game_api = {
      get_all_valid_roles = function() return {} end,
    },
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    env.scheduled[1].callback()

    luassert.truthy(#env.warnings > 0, "should warn when no valid role exists")
    luassert.truthy(
      env.warnings[1]:find("no valid role", 1, true) ~= nil,
      "should mention no valid role: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_subscription_check_missing_game_api_warns()
  _with_env({}, function(module, env, _)
    local game = _game()
    module.setup(game)
    with_patches({
      { key = "GameAPI", value = nil },
    }, function()
      env.scheduled[1].callback()
    end)

    luassert.truthy(#env.warnings > 0, "should warn when GameAPI is missing")
    luassert.truthy(
      env.warnings[1]:find("no valid role", 1, true) ~= nil,
      "should mention no valid role: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_subscription_check_role_fetch_failure_warns()
  _with_env({
    game_api = {
      get_all_valid_roles = function() error("roles boom") end,
    },
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    env.scheduled[1].callback()

    luassert.truthy(#env.warnings > 0, "should warn when get_all_valid_roles raises")
    luassert.truthy(
      env.warnings[1]:find("no valid role", 1, true) ~= nil,
      "should mention no valid role: " .. tostring(env.warnings[1])
    )
  end)
end

-- 字符串之外的非表返回(数字、false)同样按「无有效角色」降级,不得取长度炸穿。
local function _test_subscription_check_number_or_false_roles_warns()
  for _, bad_roles in ipairs({ 7, false }) do
    _with_env({
      game_api = {
        get_all_valid_roles = function() return bad_roles end,
      },
    }, function(module, env, _)
      local game = _game()
      module.setup(game)
      local ok, err = pcall(env.scheduled[1].callback)

      _assert_eq(ok, true, "non-table roles " .. tostring(bad_roles) .. " should not raise: " .. tostring(err))
      _assert_eq(#env.unit_sends, 0, "non-table roles should send nothing")
      luassert.truthy(
        env.warnings[1] ~= nil and env.warnings[1]:find("no valid role", 1, true) ~= nil,
        "should mention no valid role: " .. tostring(env.warnings[1])
      )
    end)
  end
end

local function _test_subscription_check_non_table_roles_warns()
  _with_env({
    game_api = {
      get_all_valid_roles = function() return "not a table" end,
    },
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    env.scheduled[1].callback()

    luassert.truthy(#env.warnings > 0, "should warn when roles is not a table")
    luassert.truthy(
      env.warnings[1]:find("no valid role", 1, true) ~= nil,
      "should mention no valid role: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_subscription_check_missing_method_warns()
  _with_env({
    role = {
      show_like_panel = function() end,
      get_ctrl_unit = function() return "unit_1" end,
    },
  }, function(module, env, _)
    local game = _game()
    module.setup(game)
    env.scheduled[1].callback()

    luassert.truthy(#env.warnings > 0, "should warn when is_subscribed_map_author missing")
    luassert.truthy(
      env.warnings[1]:find("is_subscribed_map_author missing", 1, true) ~= nil,
      "should mention method missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_setup_missing_set_timeout_warns()
  _with_env({}, function(module, env, _)
    with_patches({
      { key = "SetTimeOut", value = nil },
    }, function()
      module.setup(_game())
    end)

    luassert.truthy(#env.warnings > 0, "should warn when SetTimeOut is missing")
    luassert.truthy(
      env.warnings[1]:find("SetTimeOut missing", 1, true) ~= nil,
      "should mention SetTimeOut missing: " .. tostring(env.warnings[1])
    )
  end)
end

local function _test_setup_schedule_failure_warns_only()
  _with_env({}, function(module, env, _)
    with_patches({
      {
        key = "SetTimeOut",
        value = function() error("timeout boom") end,
      },
    }, function()
      module.setup(_game())
    end)

    luassert.truthy(#env.warnings > 0, "should warn when SetTimeOut raises")
  end)
end

it("test_setup_registers_three_listeners_once", _test_setup_registers_three_listeners_once)
it("test_setup_skips_registration_without_host_contract", _test_setup_skips_registration_without_host_contract)
it("test_like_click_opens_panel_and_sends_event", _test_like_click_opens_panel_and_sends_event)
it("test_collect_click_opens_panel_and_sends_event", _test_collect_click_opens_panel_and_sends_event)
it("test_subscribe_click_opens_panel_and_shows_tips", _test_subscribe_click_opens_panel_and_shows_tips)
it("test_map_enter_check_uses_zero_point_one_delay", _test_map_enter_check_uses_zero_point_one_delay)
it("test_map_enter_subscribed_sends_subscribe_event", _test_map_enter_subscribed_sends_subscribe_event)
it("test_map_enter_not_subscribed_sends_nothing", _test_map_enter_not_subscribed_sends_nothing)
it("test_subscription_event_not_sent_twice", _test_subscription_event_not_sent_twice)
it("test_subscription_send_failure_is_not_latched_and_retries", _test_subscription_send_failure_is_not_latched_and_retries)
it("test_subscription_missing_ctrl_unit_is_not_latched_and_retries", _test_subscription_missing_ctrl_unit_is_not_latched_and_retries)
it("test_subscription_missing_lua_api_is_not_latched_and_retries", _test_subscription_missing_lua_api_is_not_latched_and_retries)
it("test_like_click_without_role_warns_only", _test_like_click_without_role_warns_only)
it("test_host_call_failures_warn_only", _test_host_call_failures_warn_only)
it("test_unit_send_failure_warns_only", _test_unit_send_failure_warns_only)
it("test_unit_send_missing_ctrl_unit_warns", _test_unit_send_missing_ctrl_unit_warns)
it("test_unit_send_ctrl_unit_call_failure_warns", _test_unit_send_ctrl_unit_call_failure_warns)
it("test_unit_send_ctrl_unit_returns_nil_warns", _test_unit_send_ctrl_unit_returns_nil_warns)
it("test_unit_send_missing_lua_api_warns", _test_unit_send_missing_lua_api_warns)
it("test_show_tips_missing_global_api_warns", _test_show_tips_missing_global_api_warns)
it("test_show_tips_failure_warns_only", _test_show_tips_failure_warns_only)
it("test_subscription_check_without_valid_role_warns", _test_subscription_check_without_valid_role_warns)
it("test_subscription_check_missing_game_api_warns", _test_subscription_check_missing_game_api_warns)
it("test_subscription_check_role_fetch_failure_warns", _test_subscription_check_role_fetch_failure_warns)
it("test_subscription_check_non_table_roles_warns", _test_subscription_check_non_table_roles_warns)
it("test_subscription_check_number_or_false_roles_warns", _test_subscription_check_number_or_false_roles_warns)
it("test_subscription_check_missing_method_warns", _test_subscription_check_missing_method_warns)
it("test_setup_missing_set_timeout_warns", _test_setup_missing_set_timeout_warns)
it("test_setup_schedule_failure_warns_only", _test_setup_schedule_failure_warns_only)
end)
