-- Mutation-pinning spec for src/app/event_bridge.lua.
-- Drives M.install with a fake LuaAPI so we can capture a registered event
-- callback, invoke it, and observe that state.game is set from get_current_game.
--
require("test.bootstrap").install_package_paths()
local luassert = assert
local runtime_context = require("src.host.context")
local visual_hold = require("src.ui.visual_hold")
local event_bridge = require("src.app.event_bridge")

describe("TestEventBridgeMutation", function()
  local saved_context, lifecycle_run_or_defer
  before_each(function()
    saved_context = runtime_context.current()
    lifecycle_run_or_defer = visual_hold.run_or_defer
  end)

local function build_event_host()
  local active_callbacks = {}
  local triggers_by_name = {}
  local unregistered = {}

  local lua_api = {
    global_register_custom_event = function(name, callback)
      local trigger = { event_name = name }
      active_callbacks[trigger] = callback
      triggers_by_name[name] = trigger
      return trigger
    end,
    global_unregister_custom_event = function(trigger)
      unregistered[#unregistered + 1] = trigger
      active_callbacks[trigger] = nil
    end,
  }

  return lua_api, active_callbacks, triggers_by_name, unregistered
end

  after_each(function()
    if event_bridge.uninstall then
      event_bridge.uninstall()
    end
    visual_hold.run_or_defer = lifecycle_run_or_defer
    runtime_context.set_current(saved_context)
  end)

local function _test_uninstall_removes_both_registered_event_callbacks()
  local lua_api, active_callbacks, triggers_by_name = build_event_host()
  local saved_ctx = runtime_context.current()
  runtime_context.set_current({ env = { LuaAPI = lua_api } })

  event_bridge.install({}, function() return {} end)
  event_bridge.uninstall()

  runtime_context.set_current(saved_ctx)

  local events = require("src.foundation.events")
  luassert.is_nil(active_callbacks[triggers_by_name[events.land.tile_upgraded]])
  luassert.is_nil(active_callbacks[triggers_by_name[events.intent.need_choice]])
end

local function _test_uninstall_is_idempotent()
  local lua_api, _, _, unregistered = build_event_host()
  local saved_ctx = runtime_context.current()
  runtime_context.set_current({ env = { LuaAPI = lua_api } })

  event_bridge.install({}, function() return {} end)
  event_bridge.uninstall()
  event_bridge.uninstall()

  runtime_context.set_current(saved_ctx)

  luassert.is.equal(2, #unregistered)
end

local function _test_repeated_install_does_not_register_duplicate_events()
  local register_count = 0
  local lua_api = {
    global_register_custom_event = function(_, callback)
      register_count = register_count + 1
      return { callback = callback }
    end,
    global_unregister_custom_event = function() end,
  }
  local saved_ctx = runtime_context.current()
  runtime_context.set_current({ env = { LuaAPI = lua_api } })

  event_bridge.install({}, function() return {} end)
  event_bridge.install({}, function() return {} end)

  runtime_context.set_current(saved_ctx)

  -- lint-allow: call-count lua_api 经参数注入,重复 install 不重复注册是幂等契约
  luassert.is.equal(2, register_count)
end

local function _test_stores_the_get_current_game_result_on_state_game_when_an_event_fires_L16_nil()
  local registered = {}
  local fake_ctx = {
    env = {
      LuaAPI = {
        global_register_custom_event = function(name, callback)
          registered[name] = callback
        end,
      },
    },
  }
  local saved_ctx = runtime_context.current()
  runtime_context.set_current(fake_ctx)

  -- state.game is assigned before run_or_defer runs, so a no-op stub is enough
  -- to isolate the L16 assignment without invoking downstream handlers.
  local saved_run_or_defer = visual_hold.run_or_defer
  visual_hold.run_or_defer = function() end

  local sentinel_game = { marker = "the_current_game" }
  local state = {}
  event_bridge.install(state, function() return sentinel_game end)

  -- Invoke the first registered callback with the host's (self, _, data) shape.
  local _, callback = next(registered)
  local fired = callback ~= nil
  if callback then
    callback(nil, nil, { payload = true })
  end

  visual_hold.run_or_defer = saved_run_or_defer
  runtime_context.set_current(saved_ctx)

  luassert.truthy(fired, "at least one event must have been registered to invoke")
  -- L16 `get_current_game()` -> nil would leave state.game = nil.
  luassert.truthy(state.game == sentinel_game,
    "state.game must be the get_current_game() result; got " .. tostring(state.game))
end

-- #293 复核:install 的 3 处守卫断言 + run_or_defer 的 source 标签未测,4 个
-- survivor 全属此族;补钉后逐条击杀。

local function _test_install_asserts_missing_state_L9_nil()
  luassert.has_error.match(function()
    event_bridge.install(nil, function() end)
  end, "missing state", 1, true)
end

local function _test_install_asserts_missing_get_current_game_L10_nil()
  luassert.has_error.match(function()
    event_bridge.install({}, nil)
  end, "missing get_current_game", 1, true)
end

local function _test_install_asserts_when_event_registration_fails_L26_nil()
  -- host.register_custom_event 在 LuaAPI 缺函数时返回 false(函数存在则恒
  -- 返回 true,真实调用结果在第二返回值)——空 LuaAPI 才触发 event_bridge
  -- 的断言。
  local fake_ctx = {
    env = {
      LuaAPI = {},
    },
  }
  local saved_ctx = runtime_context.current()
  runtime_context.set_current(fake_ctx)
  local ok, err = pcall(function()
    event_bridge.install({}, function() end)
  end)
  runtime_context.set_current(saved_ctx)
  luassert.truthy(ok == false, "failed registration should assert")
  luassert.truthy(tostring(err):find("global_register_custom_event", 1, true) ~= nil,
    "assert should name the missing LuaAPI function: " .. tostring(err))
end

local function _test_run_or_defer_carries_the_runtime_event_source_L15_nil()
  local registered = {}
  local fake_ctx = {
    env = {
      LuaAPI = {
        global_register_custom_event = function(name, callback)
          registered[name] = callback
        end,
      },
    },
  }
  local saved_ctx = runtime_context.current()
  runtime_context.set_current(fake_ctx)

  local seen_source = nil
  local saved_run_or_defer = visual_hold.run_or_defer
  visual_hold.run_or_defer = function(_, _, source) seen_source = source end

  local state = {}
  event_bridge.install(state, function() return {} end)
  local _, callback = next(registered)
  local fired = callback ~= nil
  if callback then
    callback(nil, nil, { payload = true })
  end

  visual_hold.run_or_defer = saved_run_or_defer
  runtime_context.set_current(saved_ctx)

  luassert.truthy(fired, "at least one event must have been registered to invoke")
  -- L15 `"runtime_event"` -> nil would leave the source label nil.
  luassert.truthy(seen_source == "runtime_event",
    "run_or_defer must carry the runtime_event source; got " .. tostring(seen_source))
end

-- 宿主注册抛出的错误原样上抛(error level 0):不得被 event_bridge 自己的
-- 行号前缀污染,调用方据消息定位宿主侧故障。
local function _test_install_rethrows_host_registration_error_verbatim()
  local saved_ctx = runtime_context.current()
  runtime_context.set_current({ env = { LuaAPI = {
    global_register_custom_event = function()
      error("host register boom", 0)
    end,
  } } })
  local ok, err = pcall(event_bridge.install, {}, function() end)
  runtime_context.set_current(saved_ctx)
  luassert.is_false(ok)
  luassert.is.equal("host register boom", err)
end

-- 真机取证(#585):宿主拒绝注册时句柄为 nil。只有一个事件拿到句柄时,
-- 重复 install 仍不得再注册,否则已生效的事件会被重复派发。
local function _test_repeated_install_with_one_rejected_handle_does_not_duplicate_the_live_event()
  local events = require("src.foundation.events")
  local live_event_names = {}
  local lua_api = {
    global_register_custom_event = function(name)
      if name == events.land.tile_upgraded then
        return nil
      end
      live_event_names[#live_event_names + 1] = name
      return { event_name = name }
    end,
    global_unregister_custom_event = function() end,
  }
  local saved_ctx = runtime_context.current()
  runtime_context.set_current({ env = { LuaAPI = lua_api } })

  event_bridge.install({}, function() return {} end)
  event_bridge.install({}, function() return {} end)

  runtime_context.set_current(saved_ctx)

  luassert.same({ events.intent.need_choice }, live_event_names)
end


it("test_uninstall_removes_both_registered_event_callbacks", _test_uninstall_removes_both_registered_event_callbacks)
it("test_uninstall_is_idempotent", _test_uninstall_is_idempotent)
it("test_repeated_install_does_not_register_duplicate_events", _test_repeated_install_does_not_register_duplicate_events)
it("test_stores_the_get_current_game_result_on_state_game_when_an_event_fires_L16_nil", _test_stores_the_get_current_game_result_on_state_game_when_an_event_fires_L16_nil)
it("test_install_asserts_missing_state_L9_nil", _test_install_asserts_missing_state_L9_nil)
it("test_install_asserts_missing_get_current_game_L10_nil", _test_install_asserts_missing_get_current_game_L10_nil)
it("test_install_asserts_when_event_registration_fails_L26_nil", _test_install_asserts_when_event_registration_fails_L26_nil)
it("test_run_or_defer_carries_the_runtime_event_source_L15_nil", _test_run_or_defer_carries_the_runtime_event_source_L15_nil)
it("test_install_rethrows_host_registration_error_verbatim", _test_install_rethrows_host_registration_error_verbatim)
it("test_repeated_install_with_one_rejected_handle_does_not_duplicate_the_live_event",
  _test_repeated_install_with_one_rejected_handle_does_not_duplicate_the_live_event)
end)
