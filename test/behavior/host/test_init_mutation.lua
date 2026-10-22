-- Mutation-pinning specs for src/host/init.lua host_runtime.register_custom_event.
-- State shape kept inline (per view_command_mutation_pin idiom); each test asserts
-- a value that DIFFERS between the original and one specific surviving mutant.
--
-- register_custom_event guards (L19-30):
--   L20  if type(event_name) ~= "string" or type(handler) ~= "function" then return false
--   L24  local lua_api = runtime_ctx and runtime_ctx.env and runtime_ctx.env.LuaAPI or nil
--   L25  if not (lua_api and type(lua_api.global_register_custom_event) == "function") then
--   L26    return false

require("test.bootstrap").install_package_paths()
local luassert = assert
local host_runtime = require("src.host.init")
local runtime_context = require("src.host.context")

-- Run fn with runtime_context.current() forced to ctx, restoring afterwards even
-- on error so a mutant crash cannot leak state into sibling tests.
local function _with_current(ctx, fn)
  local saved = runtime_context.current()
  runtime_context.set_current(ctx)
  local ok, res = pcall(fn)
  runtime_context.set_current(saved)
  if not ok then error(res, 0) end
  return res
end

describe("TestInitMutation", function()

local function _test_rejects_a_non_string_event_name_even_when_handler_is_a_valid_function_L20_or()
  -- LuaAPI present and healthy: if the guard is bypassed, registration succeeds
  -- and the function returns true, so original (false) vs mutant (true) diverge.
  local registered = {}
  local ctx = {
    env = {
      LuaAPI = {
        global_register_custom_event = function(name, handler)
          registered[#registered + 1] = { name = name, handler = handler }
        end,
      },
    },
  }
  local result = _with_current(ctx, function()
    return host_runtime.register_custom_event(123, function() end) -- number name, fn handler
  end)
  -- Original L20: (type(123)~="string"=true) OR (type(fn)~="function"=false) -> true -> return false.
  -- Mutant  and:  true AND false -> false -> falls through -> registers -> returns true.
  luassert.truthy(result == false,
    "non-string event_name must be rejected (return false); got " .. tostring(result))
  luassert.truthy(#registered == 0,
    "rejected registration must not reach LuaAPI; saw " .. #registered .. " calls")
end

local function _test_returns_false_when_luaapi_lacks_a_callable_global_register_custom_event_L25_and()
  -- lua_api is a present table, but the registration hook is NOT a function.
  -- Original short-circuits on the failed type() check and returns false.
  -- Mutant 'or' lets a truthy lua_api satisfy the guard, then tries to CALL the
  -- non-function hook and crashes -> the direct (non-pcall) call raises, which
  -- busted records as a failure, killing the mutant.
  local ctx = { env = { LuaAPI = { global_register_custom_event = 42 } } } -- not a function
  local result = _with_current(ctx, function()
    return host_runtime.register_custom_event("evt", function() end)
  end)
  -- Original L25: not(lua_api AND type(42)=="function"=false) = not(false) = true -> return false.
  -- Mutant  or:   not(lua_api OR ...) = not(truthy) = false -> proceeds -> 42(...) -> crash.
  luassert.truthy(result == false,
    "missing callable hook must return false; got " .. tostring(result))
end

local function _test_returns_false_not_true_when_no_runtime_context_luaapi_is_available_l26_false()
  -- current()=nil -> lua_api=nil -> guard fails -> hits `return false`.
  local result = _with_current(nil, function()
    return host_runtime.register_custom_event("evt", function() end)
  end)
  -- Original L26: return false. Mutant false->true: return true.
  luassert.truthy(result == false,
    "unavailable LuaAPI must yield false; L26 mutation flips it to true. Got " .. tostring(result))
end

local function _test_returns_true_only_on_the_genuine_happy_path_positive_control_for_L26()
  -- Confirms the false/true distinction is meaningful: with a healthy hook the
  -- function DOES return true, so the L26 test above is not vacuously false.
  local ctx = { env = { LuaAPI = { global_register_custom_event = function() end } } }
  local result = _with_current(ctx, function()
    return host_runtime.register_custom_event("evt", function() end)
  end)
  luassert.truthy(result == true, "healthy registration must return true; got " .. tostring(result))
end

local function _test_schedule_forwards_with_zero_default_delay()
  -- #293:schedule 的 `delay or 0` 默认(or→and / 0→1 / 调用→nil 变异)未测。
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  local seen
  local saved_schedule = runtime_ports.schedule
  runtime_ports.schedule = function(delay, fn)
    seen = { delay = delay, fn = fn }
    return true
  end
  local fn = function() end
  local result = host_runtime.schedule(nil, fn)
  runtime_ports.schedule = saved_schedule
  luassert.truthy(seen ~= nil and seen.delay == 0,
    "schedule should default a nil delay to 0; got " .. tostring(seen and seen.delay))
  luassert.truthy(seen.fn == fn, "schedule should forward the callback")
  luassert.truthy(result == true, "schedule should return the port result")
end
local function _test_trigger_event_rejects_a_non_table_event_desc()
  -- register_trigger_event 与 register_custom_event 同款守卫:desc 非 table 时
  -- or→and 变异会放行到 LuaAPI,返回值 false/true 分叉。
  local registered = {}
  local ctx = {
    env = {
      LuaAPI = {
        global_register_trigger_event = function(desc, handler)
          registered[#registered + 1] = { desc = desc, handler = handler }
        end,
      },
    },
  }
  local result = _with_current(ctx, function()
    return host_runtime.register_trigger_event("ET_SPEC_ROLE_EXIT_GAME", function() end) -- string desc
  end)
  luassert.truthy(result == false,
    "non-table event_desc must be rejected (return false); got " .. tostring(result))
  luassert.truthy(#registered == 0,
    "rejected registration must not reach LuaAPI; saw " .. #registered .. " calls")
end

local function _test_trigger_event_returns_false_when_luaapi_lacks_callable_hook()
  local ctx = { env = { LuaAPI = { global_register_trigger_event = 42 } } } -- not a function
  local result = _with_current(ctx, function()
    return host_runtime.register_trigger_event({ "evt" }, function() end)
  end)
  luassert.truthy(result == false,
    "missing callable hook must return false; got " .. tostring(result))
end

local function _test_trigger_event_returns_false_when_no_runtime_context()
  local result = _with_current(nil, function()
    return host_runtime.register_trigger_event({ "evt" }, function() end)
  end)
  luassert.truthy(result == false,
    "unavailable LuaAPI must yield false; got " .. tostring(result))
end

local function _test_trigger_event_returns_true_and_forwards_desc_on_happy_path()
  local seen = nil
  local ctx = {
    env = {
      LuaAPI = {
        global_register_trigger_event = function(desc, handler)
          seen = { desc = desc, handler = handler }
          return "trigger-handle"
        end,
      },
    },
  }
  local desc = { "ET_SPEC_ROLE_EXIT_GAME", { tag = "role" } }
  local handler = function() end
  -- _with_current 只回传首个返回值,多值(registered, trigger)打包成表取。
  local results = _with_current(ctx, function()
    return { host_runtime.register_trigger_event(desc, handler) }
  end)
  local result, trigger = results[1], results[2]
  luassert.truthy(result == true, "healthy registration must return true; got " .. tostring(result))
  luassert.truthy(trigger == "trigger-handle", "trigger handle must be forwarded; got " .. tostring(trigger))
  luassert.truthy(seen ~= nil and seen.desc == desc and seen.handler == handler,
    "registration must forward desc and handler unchanged")
end


-- #199:输入框「输入完成」触发器按运行时 EVENT 值注册,注册参数为节点 id。
local function _with_event_table(event_table, fn)
  local saved = rawget(_G, "EVENT")
  _G.EVENT = event_table
  local ok, res = pcall(fn)
  _G.EVENT = saved
  if not ok then error(res, 0) end
  return res
end

local function _test_input_text_end_registers_runtime_event_on_node()
  local seen = nil
  local ctx = {
    env = {
      LuaAPI = {
        global_register_trigger_event = function(desc, handler)
          seen = { desc = desc, handler = handler }
          return "input-trigger"
        end,
      },
    },
  }
  local handler = function() end
  local results = _with_event_table({ UI_INPUT_TEXT_END_EVENT = "ET_UI_INPUT_TEXT_END" }, function()
    return _with_current(ctx, function()
      return { host_runtime.register_input_text_end("1519736575|2075094127", handler) }
    end)
  end)
  luassert.same({ true, "input-trigger" }, results, "registration should report success with the trigger handle")
  luassert.same({ "ET_UI_INPUT_TEXT_END", "1519736575|2075094127" }, seen and seen.desc,
    "registration should use the runtime event value and the node id")
  luassert.truthy(seen and seen.handler == handler, "handler should be forwarded unchanged")
end

local function _test_input_text_end_unavailable_without_runtime_event()
  local calls = 0
  local ctx = {
    env = { LuaAPI = { global_register_trigger_event = function() calls = calls + 1 end } },
  }
  local result = _with_event_table({}, function()
    return _with_current(ctx, function()
      return host_runtime.register_input_text_end("node", function() end)
    end)
  end)
  luassert.truthy(result == false, "missing runtime event should report unavailable; got " .. tostring(result))
  -- lint-allow: call-count 宿主注册入口是出站边界,事件缺失时不得触达宿主
  luassert.truthy(calls == 0, "missing runtime event must not reach LuaAPI")
end


it("test_rejects_a_non_string_event_name_even_when_handler_is_a_valid_function_L20_or", _test_rejects_a_non_string_event_name_even_when_handler_is_a_valid_function_L20_or)
it("test_returns_false_when_luaapi_lacks_a_callable_global_register_custom_event_L25_and", _test_returns_false_when_luaapi_lacks_a_callable_global_register_custom_event_L25_and)
it("test_returns_false_not_true_when_no_runtime_context_luaapi_is_available_l26_false", _test_returns_false_not_true_when_no_runtime_context_luaapi_is_available_l26_false)
it("test_returns_true_only_on_the_genuine_happy_path_positive_control_for_L26", _test_returns_true_only_on_the_genuine_happy_path_positive_control_for_L26)
it("test_schedule_forwards_with_zero_default_delay", _test_schedule_forwards_with_zero_default_delay)
it("test_trigger_event_rejects_a_non_table_event_desc", _test_trigger_event_rejects_a_non_table_event_desc)
it("test_input_text_end_registers_runtime_event_on_node", _test_input_text_end_registers_runtime_event_on_node)
it("test_input_text_end_unavailable_without_runtime_event", _test_input_text_end_unavailable_without_runtime_event)
it("test_trigger_event_returns_false_when_luaapi_lacks_callable_hook", _test_trigger_event_returns_false_when_luaapi_lacks_callable_hook)
it("test_trigger_event_returns_false_when_no_runtime_context", _test_trigger_event_returns_false_when_no_runtime_context)
it("test_trigger_event_returns_true_and_forwards_desc_on_happy_path", _test_trigger_event_returns_true_and_forwards_desc_on_happy_path)
end)
