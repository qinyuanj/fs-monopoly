require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- target 选择屏 Screen 深模块直测：descriptor 字段 + 路由意图 + inert 确认键。
-- 用 shared_support 的 choice_modal fixture（与 choice_routes_spec 同款）。
local registry = require("src.ui.screens_registry")
local target_screen = require("src.ui.screens.target_choice")
local schema = require("src.ui.schema.target_choice")
local runtime_state = require("src.ui.state.runtime")
local logger = require("src.foundation.log")

-- 找到第一个槽位按钮的 route spec（confirm/cancel 为 inert，排在前）。
local function _first_slot_spec(state)
  local slot_names = {}
  for _, name in ipairs(schema.slot_buttons or {}) do slot_names[name] = true end
  for _, s in ipairs(target_screen.build_route_specs(state)) do
    if slot_names[s.name] then return s end
  end
  return nil
end

local function _with_ui_model(model, fn)
  local state = {}
  runtime_state.set_ui_model(state, model)
  return fn(state)
end

local function _capturing_warn(fn)
  local original = logger.warn
  local warned = false
  logger.warn = function() warned = true end
  local ok, err = pcall(fn)
  logger.warn = original
  if not ok then error(err) end
  return warned
end

describe("TestTargetChoiceScreen", function()
it("test_exposes_a_descriptor_with_the_pinned_target_fields", function()
  local d = target_screen.descriptor()
  luassert.truthy(d.key == "target", "descriptor key is target")
  luassert.is_not_nil(d.root, "has root/canvas node")
  luassert.truthy(d.title ~= nil and d.body ~= nil, "has title and body")
  luassert.is_not_nil(d.option_buttons, "has option_buttons")
  luassert.truthy(d.slot_labels ~= nil and d.slot_projections ~= nil, "has slot label/projection nodes")
  luassert.truthy(d.confirm ~= nil and d.cancel ~= nil, "has confirm and cancel nodes")
end)

it("test_registers_itself_into_the_registry_under_its_key", function()
  luassert.is_not_nil(registry.build_choice_screens().target, "registry aggregates target descriptor")
  luassert.truthy(registry.opener_for("target") == target_screen.open, "registry maps target opener")
end)

it("test_keeps the confirm key inert (build_intent returns nil) — target auto-confirms on slot", function()
  local specs = target_screen.build_route_specs({})
  local confirm_spec
  for _, s in ipairs(specs) do
    if s.name == schema.confirm then confirm_spec = s end
  end
  luassert.is_not_nil(confirm_spec, "confirm node has a route spec")
  luassert.is_nil(confirm_spec.build_intent(), "confirm intent is inert nil by design")
end)

it("test_builds_a_choice_select_intent_for_a_slot_button_when_a_choice_is_present", function()
  -- slot 路径与 target_choice_screen.build_route_specs 等价：借 runtime model 注入 choice。
  -- 具体 fixture 复用 shared_support（见 choice_routes_spec 的 _build_choice_modal_state）。
  local specs = target_screen.build_route_specs({})
  local has_slot = false
  for _, s in ipairs(specs) do
    if s.name == schema.slot_buttons[1] then has_slot = true end
  end
  luassert.truthy(has_slot, "first slot button has a route spec")
end)

it("test_resolves_the_slots_own_index_when_the_choice_has_multiple_options", function()
  local intent = _with_ui_model(
    { choice = { id = 8, options = { { id = 21 }, { id = 22 } } } },
    function(state)
      return _first_slot_spec(state).build_intent()
    end)
  luassert.is_not_nil(intent, "first slot resolves to an intent")
  luassert.truthy(intent.type == "choice_select", "intent type is choice_select")
  luassert.truthy(intent.choice_id == 8, "intent carries the choice id")
  luassert.truthy(intent.option_id == 21, "first slot maps to its own index -> option 21")
end)

it("test_collapses_to_the_single_option_when_the_choice_has_exactly_one", function()
  local intent = _with_ui_model(
    { choice = { id = 9, options = { { id = 99 } } } },
    function(state)
      return _first_slot_spec(state).build_intent()
    end)
  luassert.is_not_nil(intent, "single-option choice resolves to an intent")
  luassert.truthy(intent.option_id == 99, "single-option choice collapses to option 99")
end)

it("test_warns_and_returns_nil_when_no_choice_is_present", function()
  local intent
  local warned = _capturing_warn(function()
    intent = _with_ui_model({}, function(state)
      return _first_slot_spec(state).build_intent()
    end)
  end)
  luassert.is_nil(intent, "missing choice yields nil intent")
  luassert.truthy(warned, "missing choice logs a warning")
end)

it("test_warns_and_returns_nil_when_the_option_cannot_be_resolved", function()
  local intent
  local warned = _capturing_warn(function()
    intent = _with_ui_model({ choice = { id = 4, options = {} } }, function(state)
      return _first_slot_spec(state).build_intent()
    end)
  end)
  luassert.is_nil(intent, "unresolvable option yields nil intent")
  luassert.truthy(warned, "unresolvable option logs a warning")
end)


end)
