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

--[[ mutate4lua-manifest
version=4
projectHash=b1ad83602288d441
scope.0.id=chunk:src/ui/coord/event_actor_policy.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=59
scope.0.semanticHash=b81f7028834f9aa2
scope.1.id=function:policy.is_actor_bound_ui_button
scope.1.kind=function
scope.1.startLine=8
scope.1.endLine=10
scope.1.semanticHash=60c4deec8574db8a
scope.2.id=function:policy.requires_event_actor
scope.2.kind=function
scope.2.startLine=12
scope.2.endLine=14
scope.2.semanticHash=f1ce1850b7232305
scope.3.id=function:policy.uses_local_actor
scope.3.kind=function
scope.3.startLine=16
scope.3.endLine=18
scope.3.semanticHash=f1ce1850b7232305
scope.4.id=function:policy.is_optional_event_actor
scope.4.kind=function
scope.4.startLine=20
scope.4.endLine=22
scope.4.semanticHash=f1ce1850b7232305
scope.5.id=function:policy.resolve_actor_role_id
scope.5.kind=function
scope.5.startLine=24
scope.5.endLine=29
scope.5.semanticHash=d395bbf092ed01ed
scope.6.id=function:policy.reject_missing_actor
scope.6.kind=function
scope.6.startLine=31
scope.6.endLine=40
scope.6.semanticHash=66777c1bb3765701
scope.7.id=function:policy.attach_event_actor
scope.7.kind=function
scope.7.startLine=42
scope.7.endLine=56
scope.7.semanticHash=3cdf7393699a3457
]]
