local runtime_ui = require("src.ui.render.support.runtime_ui")

local M = {}

local function _runtime_from_state(state)
  local from_state = state and state.presentation_runtime
  if from_state and from_state.runtime then
    return from_state.runtime
  end
  return nil
end

function M.resolve(state, deps)
  if deps and deps.runtime then
    return deps.runtime
  end
  return _runtime_from_state(state) or runtime_ui
end

return M

