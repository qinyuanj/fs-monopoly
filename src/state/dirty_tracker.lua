local dirty_tracker = {}
local _dirty_keys = {
  "any",
  "players",
  "board_tiles",
  "turn",
  "market",
  "turn_countdown",
  "inventory",
}

local valid_domains = {}
for _, key in ipairs(_dirty_keys) do
  valid_domains[key] = true
end

function dirty_tracker.new()
  return dirty_tracker.reset({})
end

function dirty_tracker.mark(d, domain)
  assert(valid_domains[domain], "unknown dirty domain: " .. tostring(domain))
  d.any = true
  d[domain] = true
end

function dirty_tracker.mark_turn(game)
  if game and game.dirty then
    dirty_tracker.mark(game.dirty, "turn")
  end
end

function dirty_tracker.mark_inventory(d)
  d.any = true
  d.players = true
  d.inventory = true
end

function dirty_tracker.merge_into(target, dirty)
  if type(target) ~= "table" or type(dirty) ~= "table" then
    return target
  end
  for _, key in ipairs(_dirty_keys) do
    if dirty[key] then
      target[key] = true
    end
  end
  return target
end

function dirty_tracker.reset(d)
  for _, key in ipairs(_dirty_keys) do
    d[key] = false
  end
  return d
end

local _consume_snapshot = {}

function dirty_tracker.consume(d)
  for k in pairs(_consume_snapshot) do
    _consume_snapshot[k] = nil
  end
  for _, key in ipairs(_dirty_keys) do
    _consume_snapshot[key] = d[key]
    d[key] = false
  end
  return _consume_snapshot
end

return dirty_tracker

