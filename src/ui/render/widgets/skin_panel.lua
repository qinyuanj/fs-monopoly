local nodes = require("src.ui.schema.skin")
local panel_runtime = require("src.ui.render.support.panel_runtime")
local ui_controls = require("src.ui.render.support.ui_controls")
local slot_views = require("src.ui.render.widgets.skin_panel_slot_views")
local skin_buttons = require("src.ui.render.widgets.skin_panel_buttons")
local skin_cards = require("src.ui.render.widgets.skin_panel_cards")

local skin_panel_view = {}

local _resolve_runtime = panel_runtime.resolve

local function _refresh_static_nodes(ui)
  ui_controls.set_controls_state(ui, nodes.static_visual_nodes, { visible = true, touch_enabled = false })
  ui_controls.set_control_state(ui, nodes.activity_background, { visible = true, touch_enabled = true })
  ui_controls.set_controls_state(ui, nodes.passthrough_nodes, { touch_enabled = false })
  ui_controls.set_control_state(ui, nodes.close_button, { visible = true, touch_enabled = true })
end

function skin_panel_view.refresh_slots(state, catalog, deps)
  local ui = assert(state.ui, "missing ui")
  local runtime = _resolve_runtime(state, deps)
  local page_views = slot_views.build_page(state, catalog)

  _refresh_static_nodes(ui)

  for slot in ipairs(nodes.card_images) do
    local view = page_views[slot]
    skin_cards.refresh_slot_visuals(state, ui, runtime, slot, view)
    skin_buttons.refresh_button(ui, slot, view)
  end
end

return skin_panel_view

