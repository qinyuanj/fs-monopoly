local cosmetics_port = require("src.ui.seams.cosmetics").build()
local transaction_state = cosmetics_port.transaction_state

local state = {}

function state.ensure(root_state)
  local panel, err = transaction_state.ensure_panel(root_state)
  return assert(panel, err or "missing_state")
end

return state

