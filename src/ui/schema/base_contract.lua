local nodes = require("src.ui.schema.base")
local debug_nodes = require("src.ui.schema.debug")

return {
  key = "base",
  canvas = nodes.canvas,
  action_log = {
    label = debug_nodes.log_text,
    toggle_targets = { nodes.action_log_button },
  },
}

