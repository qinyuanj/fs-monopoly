local dirty_tracker = require("src.state.dirty_tracker")

local deferred_dirty = {}

deferred_dirty.new_bucket = dirty_tracker.new

deferred_dirty.merge_into = dirty_tracker.merge_into

function deferred_dirty.reset(hold)
  hold.deferred_dirty = deferred_dirty.new_bucket()
end

function deferred_dirty.defer(hold, dirty)
  deferred_dirty.merge_into(hold.deferred_dirty, dirty)
  return hold.deferred_dirty
end

return deferred_dirty

