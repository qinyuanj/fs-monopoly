local ui_runtime_state = require("src.ui.state.runtime")

local common = {}

function common.build_log_prefix()
  return "[Eggy]"
end

function common.log_once(state, level, key, ...)
  ui_runtime_state.log_once(state, level, key, ...)
end

function common.get_ui_state(state)
  return state and state.ui or nil
end

return common

