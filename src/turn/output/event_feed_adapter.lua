local event_log = require("src.state.event_log")
local timing = require("src.config.gameplay.timing")
local logger = require("src.foundation.log")
local tip_policy = require("src.config.tip_policy")
local tip_queue = require("src.foundation.tips")

local Adapter = {}
Adapter.__index = Adapter

function Adapter.new(game, sync_event_log)
  local self = setmetatable({}, Adapter)
  self.game = game
  self.sync_event_log = sync_event_log
  game.state = game.state or {}
  game.state.event_log = game.state.event_log or event_log.new()
  return self
end

local function _resolve_policy(kind)
  if kind == nil then
    return nil
  end
  return tip_policy[kind]
end

local function _should_log(policy)
  if policy and policy.log == false then
    return false
  end
  return true
end

local function _should_tip(event, policy)
  if policy and policy.tip ~= nil then
    return policy.tip == true
  end
  return event.tip ~= false
end

local function _build_tip_intent(event)
  return {
    text = event.text,
    duration = event.tip_duration or timing.event_tip_default_seconds or 1.0,
    dedupe_key = event.tip_dedupe_key,
    blocks_inter_turn = event.blocks_inter_turn == true,
    source = event.source or ("event_feed:" .. tostring(event.kind)),
  }
end

local function _enqueue_tip(game, event, intent)
  local port = game.tip_output_port
  if port and type(port.enqueue) == "function" then
    port.enqueue(game, intent)
    return
  end
  logger.warn("[event_feed_adapter]", "tip_output_port missing, falling back to tip_queue | event:", tostring(event.kind))
  tip_queue.enqueue(intent)
end

function Adapter:publish(game, event)
  local policy = _resolve_policy(event.kind)

  if _should_log(policy) then
    event_log.append(game.state.event_log, event)
    if type(self.sync_event_log) == "function" then
      self.sync_event_log()
    end
  end

  if not _should_tip(event, policy) then
    return true
  end

  _enqueue_tip(game, event, _build_tip_intent(event))
  return true
end

return Adapter

