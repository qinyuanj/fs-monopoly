require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- remote 选择屏 Screen 深模块直测：descriptor 字段 + 路由意图 + registry 注册。
local registry = require("src.ui.screens_registry")
local remote_screen = require("src.ui.screens.remote_choice")
local schema = require("src.ui.schema.remote_choice")
local runtime_state = require("src.ui.state.runtime")
local logger = require("src.foundation.log")

-- 借 runtime ui_model 注入 choice，直接执行 build_intent 闭包体。
local function _with_ui_model(model, fn)
  local state = {}
  runtime_state.set_ui_model(state, model)
  return fn(state)
end

-- 抑制并捕获 logger.warn，保持测试输出干净且可断言告警发生。
local function _capturing_warn(fn)
  local original = logger.warn
  local warned = false
  logger.warn = function() warned = true end
  local ok, err = pcall(fn)
  logger.warn = original
  if not ok then error(err) end
  return warned
end

describe("TestRemoteChoiceScreen", function()
it("test_exposes_a_descriptor_with_the_pinned_remote_fields", function()
  local d = remote_screen.descriptor()
  luassert.truthy(d.key == "remote", "descriptor key is remote")
  luassert.is_not_nil(d.root, "has root/canvas node")
  luassert.is_not_nil(d.title, "has title")
  luassert.is_not_nil(d.body, "has body")
  luassert.is_not_nil(d.option_buttons, "has option_buttons")
end)

it("test_registers_itself_into_the_registry_under_its_key", function()
  luassert.is_not_nil(registry.build_choice_screens().remote, "registry aggregates remote descriptor")
  luassert.truthy(registry.opener_for("remote") == remote_screen.open, "registry maps remote opener")
end)

it("test_builds_a_route_spec_for_every_option_node", function()
  local specs = remote_screen.build_route_specs({})
  local spec_names = {}
  for _, s in ipairs(specs) do
    spec_names[s.name] = true
  end
  for _, name in ipairs(schema.options) do
    luassert.truthy(spec_names[name], "option node has route spec: " .. name)
  end
end)

it("test_returns_a_choice_select_intent_for_an_option_when_choice_is_present", function()
  local intent = _with_ui_model(
    { choice = { id = 7, options = { { id = 11 }, { id = 12 } } } },
    function(state)
      local specs = remote_screen.build_route_specs(state)
      return specs[1].build_intent()
    end)
  luassert.is_not_nil(intent, "first option resolves to an intent")
  luassert.truthy(intent.type == "choice_select", "intent type is choice_select")
  luassert.truthy(intent.choice_id == 7, "intent carries the choice id")
  luassert.truthy(intent.option_id == 11, "first option maps to option id 11")
end)

it("test_warns_and_returns_nil_when_no_choice_is_present", function()
  local intent
  local warned = _capturing_warn(function()
    intent = _with_ui_model({}, function(state)
      return remote_screen.build_route_specs(state)[1].build_intent()
    end)
  end)
  luassert.is_nil(intent, "missing choice yields nil intent")
  luassert.truthy(warned, "missing choice logs a warning")
end)

it("test_warns_and_returns_nil_when_the_option_cannot_be_resolved", function()
  local intent
  local warned = _capturing_warn(function()
    intent = _with_ui_model({ choice = { id = 3, options = {} } }, function(state)
      return remote_screen.build_route_specs(state)[1].build_intent()
    end)
  end)
  luassert.is_nil(intent, "unresolvable option yields nil intent")
  luassert.truthy(warned, "unresolvable option logs a warning")
end)


end)
