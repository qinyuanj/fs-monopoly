require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local support = require("test.support.shared_support")
local _with_patches = support.with_patches
local _build_role_with_events = support.build_role_with_events
local _has_event = support.has_event
local view_command = require("src.ui.input.view_command")
local presentation_ports = require("src.ui.ports")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local ui_events = require("src.ui.coord.ui_events")
local skin_intents = require("src.ui.screens.skin_panel")
local skin_nodes = require("src.ui.schema.skin")
local fake_skin_ownership = require("test.support.fake_skin_ownership")

local function _no_op() end

local function _build_ui_state()
  return {
    set_visible = _no_op,
    set_label = _no_op,
    set_button = _no_op,
    set_touch_enabled = _no_op,
    market_active = false,
    choice_active = false,
    popup_active = false,
    move_active = false,
    query_node = function() return {} end,
  }
end

describe("TestSkinPanelIntentCanvasOpenViaViewCommandDispatch", function()
local restore_seam

before_each(function()
  restore_seam = fake_skin_ownership.install(fake_skin_ownership.new())
end)

after_each(function()
  restore_seam()
end)

it("test_open_skin_panel_intent_switches_canvas_for_resolved_role", function()
  local clicker_events = {}
  local other_events = {}
  local clicker = _build_role_with_events(1, clicker_events)
  local other = _build_role_with_events(2, other_events)
  local state = {
    ui = _build_ui_state(),
    runtime_asset_context = { refs = { images = {} } },
    view_command_port = presentation_ports.build_view_command(presentation_ports.build()),
  }

  _with_patches({
    { target = runtime_ports, key = "resolve_role", value = function(role_id)
      if tostring(role_id) == "1" then return clicker end
      if tostring(role_id) == "2" then return other end
      return nil
    end },
    { target = ui_events, key = "roles", value = { clicker, other } },
  }, function()
    view_command.dispatch(state, { type = "open_skin_panel", actor_role_id = 1 })
  end)

  luassert.truthy(state.ui.skin_panel and state.ui.skin_panel.open == true,
    "model state must mark skin panel open")
  luassert.truthy(_has_event(clicker_events, "显示皮肤商店"),
    "clicker role must receive 显示皮肤商店 — model open without canvas show is the v102 bug")
  luassert.truthy(not _has_event(other_events, "显示皮肤商店"),
    "non-clicker role must not have their canvas yanked to skin shop")
end)

it("test_open_skin_panel_intent_broadcasts_when_actor_role_id_missing", function()
  local role1_events = {}
  local role2_events = {}
  local role1 = _build_role_with_events(1, role1_events)
  local role2 = _build_role_with_events(2, role2_events)
  local state = {
    ui = _build_ui_state(),
    runtime_asset_context = { refs = { images = {} } },
    view_command_port = presentation_ports.build_view_command(presentation_ports.build()),
  }

  _with_patches({
    { target = runtime_ports, key = "resolve_role", value = function() return nil end },
    { target = ui_events, key = "roles", value = { role1, role2 } },
  }, function()
    view_command.dispatch(state, { type = "open_skin_panel" })
  end)

  luassert.truthy(state.ui.skin_panel and state.ui.skin_panel.open == true,
    "model state must mark skin panel open even without actor_role_id")
  luassert.truthy(_has_event(role1_events, "显示皮肤商店"),
    "broadcast path must reach role1 when actor_role_id is missing")
  luassert.truthy(_has_event(role2_events, "显示皮肤商店"),
    "broadcast path must reach role2 when actor_role_id is missing")
end)
end)

describe("TestSkinPanelIntentCanvasActionButtonRouting", function()
local function _spec_named(specs, name)
  for _, spec in ipairs(specs) do
    if spec.name == name then
      return spec
    end
  end
  return nil
end

local fake
local restore_seam

local function _state_with(selected)
  fake.own(1, "s1")
  fake.own(1, "s2")
  if selected ~= nil then
    fake.wear(1, selected)
  end
  return {
    ui = {
      skin_panel = {
        role_id = 1,
        page_index = 1,
      },
    },
  }
end

before_each(function()
  fake = fake_skin_ownership.new({
    catalog = {
      { product_id = "s1", name = "皮肤一" },
      { product_id = "s2", name = "皮肤二" },
    },
  })
  restore_seam = fake_skin_ownership.install(fake)
end)

after_each(function()
  restore_seam()
end)

it("test_action_button_routes_activate_slot_for_equipped_slot", function()
  -- The input route should report the clicked slot. The transaction flow owns
  -- whether that activation equips or unequips.
  local state = _state_with("s1")
  local spec = _spec_named(skin_intents.build_route_specs(state), skin_nodes.action_buttons[1])
  luassert.is_not_nil(spec, "slot 1 action button must have a canvas route")
  local intent = spec.build_intent()
  luassert.truthy(intent.type == "skin_panel_action", "route must dispatch a skin_panel_action intent")
  luassert.truthy(intent.action.type == "activate_slot",
    "action button route should leave equip/unequip selection to the transaction flow")
  luassert.truthy(intent.action.slot_index == 1, "activate_slot intent must carry the clicked slot index")
end)

it("test_action_button_routes_activate_slot_for_unequipped_slot", function()
  local state = _state_with("s1")
  local spec = _spec_named(skin_intents.build_route_specs(state), skin_nodes.action_buttons[2])
  luassert.is_not_nil(spec, "slot 2 action button must have a canvas route")
  local intent = spec.build_intent()
  luassert.truthy(intent.action.type == "activate_slot", "non-equipped slot's button should emit activate_slot")
  luassert.truthy(intent.action.slot_index == 2, "activate_slot intent must carry the clicked slot index")
end)

it("test_action_intent_does_not_read_live_equipped_state", function()
  local state = _state_with(nil)
  local specs = skin_intents.build_route_specs(state)
  local spec = _spec_named(specs, skin_nodes.action_buttons[1])
  luassert.is_not_nil(spec, "slot 1 action button must have a canvas route")
  luassert.truthy(spec.build_intent().action.type == "activate_slot",
    "nothing equipped should still route through activate_slot")
  fake.wear(1, "s1")
  luassert.truthy(spec.build_intent().action.type == "activate_slot",
    "equipped state changes should not alter the input-layer action")
end)


end)
