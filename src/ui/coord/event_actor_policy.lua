local local_actor_resolver = require("src.ui.seams.local_actor_resolver")
local tip_queue = require("src.foundation.tips")
local logger = require("src.foundation.log")
local command_policy = require("src.ui.input.command_policy")

local policy = {}

function policy.requires_event_actor(intent)
  return command_policy.requires_event_actor(intent)
end

function policy.uses_local_actor(intent)
  return command_policy.uses_local_actor(intent)
end

function policy.is_optional_event_actor(intent)
  return command_policy.is_optional_event_actor(intent)
end

function policy.resolve_actor_role_id(state, intent, data)
  if policy.uses_local_actor(intent) then
    return local_actor_resolver.resolve_from_event(state, data)
  end
  return local_actor_resolver.resolve_turn_bound(state, data)
end

function policy.reject_missing_actor(intent)
  tip_queue.enqueue({
    text = "当前操作缺少玩家上下文，已忽略",
    duration = 2.0,
    dedupe_key = "missing_actor:" .. tostring(intent.type) .. ":" .. tostring(intent.id),
    blocks_inter_turn = false,
    source = "ui.missing_actor",
  })
  logger.warn("ui intent rejected: missing actor_role_id", tostring(intent.type), tostring(intent.id))
end

function policy.attach_event_actor(state, intent, data)
  if not policy.requires_event_actor(intent) or intent.actor_role_id ~= nil then
    return true
  end
  local actor_role_id = policy.resolve_actor_role_id(state, intent, data)
  if actor_role_id == nil then
    if policy.is_optional_event_actor(intent) then
      return true
    end
    policy.reject_missing_actor(intent)
    return false
  end
  intent.actor_role_id = actor_role_id
  return true
end

return policy

