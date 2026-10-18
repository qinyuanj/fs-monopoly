local service = require("src.turn.deadlines.service")
local force_skip = require("src.turn.deadlines.force_skip")
local choice_resolution = require("src.turn.deadlines.choice_resolution")

local M = {
  start = service.start,
  cancel = service.cancel,
  peek = service.peek,
  tick = service.tick,
  is_active = service.is_active,
}

force_skip.install(M)
choice_resolution.install(M)

return M

