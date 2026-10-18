local release_scheduler = {}
local event_log = require("src.state.event_log")

local release_priority = {
  board_visual_sync = 1,
  runtime_event = 2,
  tile_update = 3,
  owner_change = 4,
  bankruptcy_clear = 5,
  popup = 6,
}

function release_scheduler.ensure_buffers(hold)
  hold.release_callbacks = hold.release_callbacks or {}
end

function release_scheduler.reset(hold)
  hold.release_callbacks = {}
end

function release_scheduler.register(hold, key, fn, opts)
  assert(type(fn) == "function", "missing release callback")
  opts = opts or {}
  hold.release_callbacks[#hold.release_callbacks + 1] = {
    key = key,
    fn = fn,
    order = #hold.release_callbacks + 1,
    priority = release_priority[key] or opts.priority or 100,
  }
  return fn
end

local function _sort_callbacks(release_callbacks)
  table.sort(release_callbacks, function(left, right)
    if left.priority ~= right.priority then
      return left.priority < right.priority
    end
    return left.order < right.order
  end)
end

function release_scheduler.replay(hold)
  event_log.flush_buffer(hold)
  _sort_callbacks(hold.release_callbacks)
  for _, entry in ipairs(hold.release_callbacks) do
    if type(entry.fn) == "function" then
      entry.fn()
    end
  end
end

function release_scheduler.register_deferred_replay(hold, key, replay, ...)
  local replay_args = { ... }
  return release_scheduler.register(hold, key, function()
    if type(replay) == "function" then
      return replay(table.unpack(replay_args))
    end
    return nil
  end)
end

return release_scheduler

