local nodes = require("src.ui.schema.popup")

local intents = {}

local function _dismiss_nodes(state)
  local popup = state.ui and state.ui.popup_screen or nil
  return popup and popup.dismiss_nodes or nodes.dismiss_nodes
end

local function _popup_confirm_intent(state)
  if state.ui and state.ui.popup_active then
    return { type = "popup_confirm" }
  end
  return nil
end

function intents.build(state)
  local specs = {}
  local dismiss_nodes = _dismiss_nodes(state)
  if type(dismiss_nodes) ~= "table" then
    return specs
  end
  for _, name in ipairs(dismiss_nodes) do
    specs[#specs + 1] = {
      name = name,
      build_intent = function()
        return _popup_confirm_intent(state)
      end,
    }
  end
  return specs
end

return intents

