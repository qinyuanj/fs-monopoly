local event_feed = {}

--- @param game table
--- @param event { kind: string, text: string, tip: boolean?, tip_duration: number?, tip_dedupe_key: string?, blocks_inter_turn: boolean?, source: string? }
--- @return boolean
local function _has_event_inputs(game, event)
  return game ~= nil and event ~= nil
end

local function _valid_event(event)
  return type(event.kind) == "string" and type(event.text) == "string"
end

local function _publish_port(game)
  local port = game.event_feed_port
  if port and type(port.publish) == "function" then
    return port
  end
  return nil
end

local function _bool_or_false(value)
  return value and true or false
end

function event_feed.publish(game, event)
  if not _has_event_inputs(game, event) then
    return false
  end
  if not _valid_event(event) then
    return false
  end
  local port = _publish_port(game)
  if port == nil then
    return false
  end
  return _bool_or_false(port:publish(game, event))
end

return event_feed

