local logger = require("src.foundation.log")

local move_anim_debug = {}

function move_anim_debug.enabled()
  return logger.is_anim_debug_enabled()
end

function move_anim_debug.log(...)
  if not move_anim_debug.enabled() then
    return
  end
  logger.info_unlimited("[MoveAnim]", ...)
end

return move_anim_debug

