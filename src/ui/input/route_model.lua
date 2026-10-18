local runtime_state = require("src.ui.state.runtime")

local route_model = {}

local function _current_model(state)
  return runtime_state.get_ui_model(state)
end

function route_model.field(state, key)
  local current_model = _current_model(state)
  return current_model and current_model[key] or nil
end

function route_model.choice(state)
  return route_model.field(state, "choice")
end

function route_model.market(state)
  return route_model.field(state, "market")
end

return route_model

