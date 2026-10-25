-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local view_command = require("src.ui.input.view_command")

describe("TestViewCommand", function()

it("test_dispatch_returns_false_with_no_state_ports_and_nil_intent", function()
  local result = view_command.dispatch({}, nil)
  luassert.truthy(result == false, "expected false for nil intent")
end)

it("test_dispatch_returns_false_with_no_state_ports_and_unknown_intent_type", function()
  local result = view_command.dispatch({}, { type = "not_a_real_action_xyz" })
  luassert.truthy(result == false, "expected false for unknown intent type")
end)

it("test_dispatch_delegates_to_ports_view_command_when_available", function()
  local captured = nil
  local state = {
    view_command_port = {
      dispatch = function(_, intent)
        captured = intent
        return true
      end,
    },
  }
  local intent = { type = "some_action" }
  local result = view_command.dispatch(state, intent)
  luassert.truthy(result == true, "expected true from ports dispatch")
  luassert.truthy(captured == intent, "expected intent forwarded to ports")
end)

it("test_dispatch_returns_false_when_ports_dispatch_returns_non_true", function()
  local state = {
    view_command_port = {
      dispatch = function() return false end,
    },
  }
  local result = view_command.dispatch(state, { type = "x" })
  luassert.truthy(result == false, "expected false when ports dispatch returns false")
end)

it("test_dispatch_returns_false_when_ports_dispatch_returns_nil", function()
  local state = {
    view_command_port = {
      dispatch = function() return nil end,
    },
  }
  local result = view_command.dispatch(state, { type = "x" })
  luassert.truthy(result == false, "expected false when ports dispatch returns nil")
end)

it("test_dispatch_warns_and_returns_false_when_the_view_command_port_is_missing", function()
  local logger = require("src.foundation.log")
  local warn_calls = {}
  local saved_warn = logger.warn
  logger.warn = function(...) warn_calls[#warn_calls + 1] = { ... } end
  local ok, result = pcall(view_command.dispatch, {}, { type = "popup_confirm" })
  logger.warn = saved_warn
  luassert.truthy(ok, "expected no error for popup_confirm without ports")
  luassert.truthy(result == false, "expected false when port is missing")
  luassert.truthy(#warn_calls == 1, "expected one warn for missing port, got " .. #warn_calls)
  local found = false
  for _, arg in ipairs(warn_calls[1]) do
    if tostring(arg):find("popup_confirm", 1, true) then found = true end
  end
  luassert.truthy(found, "warn must include the dropped intent type")
end)


end)
