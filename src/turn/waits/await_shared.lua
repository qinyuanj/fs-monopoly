local dirty_tracker = require("src.state.dirty_tracker")

local shared = {}

shared.WAIT = { wait = true }
shared.DONE = { done = true }

function shared.unpack_next(args)
  args = args or {}
  return args.next_state, args.next_args
end

shared.mark_dirty = dirty_tracker.mark_turn

return shared

