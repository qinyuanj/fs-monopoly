require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- secondary_confirm 选择屏 Screen 深模块直测：descriptor 字段 + 路由意图 + registry 注册。
local registry = require("src.ui.screens_registry")
local secondary_screen = require("src.ui.screens.secondary_confirm")
local schema = require("src.ui.schema.secondary_confirm")
local modal_state = require("src.ui.state.modal")
local runtime_state = require("src.ui.state.runtime")

describe("TestSecondaryConfirmScreen", function()
it("test_exposes_a_descriptor_with_the_pinned_secondary_confirm_fields", function()
  local d = secondary_screen.descriptor()
  luassert.truthy(d.key == "secondary_confirm", "descriptor key is secondary_confirm")
  luassert.is_not_nil(d.root, "has root/canvas node")
  luassert.is_not_nil(d.title, "has title")
  luassert.is_not_nil(d.body, "has body")
  luassert.is_not_nil(d.confirm, "has confirm node")
  luassert.is_not_nil(d.cancel, "has cancel node")
end)

it("test_registers_itself_into_the_registry_under_its_key", function()
  luassert.is_not_nil(registry.build_choice_screens().secondary_confirm, "registry aggregates secondary_confirm descriptor")
  luassert.truthy(registry.opener_for("secondary_confirm") == secondary_screen.open, "registry maps secondary_confirm opener")
end)

it("test_builds_a_confirm_route_spec_that_uses_choice_confirm_intent", function()
  local specs = secondary_screen.build_route_specs({})
  local confirm_spec
  for _, s in ipairs(specs) do
    if s.name == schema.confirm then confirm_spec = s end
  end
  luassert.is_not_nil(confirm_spec, "confirm node has a route spec")
  luassert.is_not_nil(confirm_spec.build_intent, "confirm spec has build_intent")
end)

it("test_builds_a_cancel_route_spec_that_uses_choice_cancel_intent", function()
  local specs = secondary_screen.build_route_specs({})
  local cancel_spec
  for _, s in ipairs(specs) do
    if s.name == schema.cancel then cancel_spec = s end
  end
  luassert.is_not_nil(cancel_spec, "cancel node has a route spec")
  luassert.is_not_nil(cancel_spec.build_intent, "cancel spec has build_intent")
end)

-- build_intent 必须真的被调用:只断言「闭包存在」杀不掉 ui_event_intents
-- require → nil 的变异(闭包惰性引用,永不求值)。
it("test_confirm_build_intent_returns_a_choice_select_intent", function()
  local state = {}
  runtime_state.set_ui_model(state, { choice = { id = "c9" } })
  modal_state.open_choice(state, "c9", { "opt1" }, "opt1")
  local specs = secondary_screen.build_route_specs(state)
  local confirm_spec
  for _, s in ipairs(specs) do
    if s.name == schema.confirm then confirm_spec = s end
  end
  local intent = confirm_spec.build_intent()
  luassert.truthy(intent ~= nil and intent.type == "choice_select",
    "confirm intent is a choice_select")
  luassert.truthy(intent.choice_id == "c9", "confirm intent carries the pending choice id")
  luassert.truthy(intent.option_id == "opt1", "confirm intent carries the selected option")
end)

it("test_cancel_build_intent_returns_a_choice_cancel_intent", function()
  local state = {}
  runtime_state.set_ui_model(state, { choice = { id = "c9" } })
  local specs = secondary_screen.build_route_specs(state)
  local cancel_spec
  for _, s in ipairs(specs) do
    if s.name == schema.cancel then cancel_spec = s end
  end
  local intent = cancel_spec.build_intent()
  luassert.truthy(intent ~= nil and intent.type == "choice_cancel",
    "cancel intent is a choice_cancel")
  luassert.truthy(intent.choice_id == "c9", "cancel intent carries the pending choice id")
end)


end)
