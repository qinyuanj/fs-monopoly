local nodes = require("src.ui.schema.skin")

local M = {}

local function _set_optional_ui_value(ui, method_name, node_name, value)
  if value == nil then
    return
  end
  local setter = ui[method_name]
  if setter then
    setter(ui, node_name, value)
  end
end

function M.refresh_button(ui, slot, view)
  local button_name = nodes.action_buttons[slot]
  if not button_name then
    return
  end
  view = view or {}
  _set_optional_ui_value(ui, "set_button", button_name, view.button_text)
  _set_optional_ui_value(ui, "set_visible", button_name, view.has_skin == true)
  _set_optional_ui_value(ui, "set_touch_enabled", button_name, view.button_touch_enabled)
end

return M

