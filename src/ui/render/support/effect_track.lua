local runtime_ports = require("src.foundation.ports.runtime_ports")

local effect_track = {}

local active_tokens = {}
local next_token_id = 1
local timeout_seconds = 10.0

local function _active_count()
  local count = 0
  for _ in pairs(active_tokens) do
    count = count + 1
  end
  return count
end

local function _complete(token)
  if token == nil then
    return
  end
  token.completed = true
  active_tokens[token.token_id] = nil
  if type(token.on_complete) == "function" then
    token.on_complete(token)
  end
end

function effect_track.spawn(id, kind, duration, on_complete)
  local token_id = next_token_id
  next_token_id = next_token_id + 1
  local token = {
    id = id,
    token_id = token_id,
    kind = kind,
    duration = duration or 0,
    on_complete = on_complete,
    spawned_at = runtime_ports.wall_now_seconds(),
    completed = false,
  }
  active_tokens[token_id] = token

  local effective_timeout = (duration or 0) + timeout_seconds
  runtime_ports.schedule(effective_timeout, function()
    if not token.completed then
      _complete(token)
    end
  end)

  return token
end

function effect_track.cancel(token)
  if token == nil or token.completed then
    return false
  end
  token.completed = true
  active_tokens[token.token_id] = nil
  return true
end

function effect_track.is_idle()
  return _active_count() == 0
end

function effect_track.await_all(callback)
  if effect_track.is_idle() then
    if type(callback) == "function" then
      callback()
    end
    return true
  end

  local function _poll()
    if effect_track.is_idle() then
      if type(callback) == "function" then
        callback()
      end
      return
    end
    runtime_ports.schedule(0.05, _poll)
  end
  runtime_ports.schedule(0.05, _poll)
  return false
end

local function _pressure()
  local count = _active_count()
  if count <= 1 then
    return 0
  end
  if count <= 3 then
    return 0.3
  end
  if count <= 6 then
    return 0.6
  end
  return 0.9
end

local pressure_scale = {
  { threshold = 0,   scale = 1.0 },
  { threshold = 0.3, scale = 0.5 },
  { threshold = 0.6, scale = 0.25 },
  { threshold = 0.9, scale = 0.15 },
}

function effect_track.scaled_duration(base)
  local p = _pressure()
  local scale = 1.0
  for i = #pressure_scale, 1, -1 do
    if p >= pressure_scale[i].threshold then
      scale = pressure_scale[i].scale
      break
    end
  end
  return base * scale
end

function effect_track.reset()
  active_tokens = {}
  next_token_id = 1
end

return effect_track

--[[ mutate4lua-manifest
version=4
projectHash=64bc94d097410050
scope.0.id=chunk:src/ui/render/support/effect_track.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=182
scope.0.semanticHash=34bbf4dc492611cc
scope.1.id=function:_active_count
scope.1.kind=function
scope.1.startLine=12
scope.1.endLine=18
scope.1.semanticHash=c5b9168c2388a2bc
scope.2.id=function:_complete
scope.2.kind=function
scope.2.startLine=20
scope.2.endLine=29
scope.2.semanticHash=60d1c31d54bcbfab
scope.3.id=function:effect_track.spawn
scope.3.kind=function
scope.3.startLine=31
scope.3.endLine=53
scope.3.semanticHash=fb637fab3f789fbf
scope.4.id=function:<anonymous>
scope.4.kind=function
scope.4.startLine=46
scope.4.endLine=50
scope.4.semanticHash=8836a44c9b06df54
scope.5.id=function:effect_track.cancel
scope.5.kind=function
scope.5.startLine=55
scope.5.endLine=62
scope.5.semanticHash=7e4496753daad7c7
scope.6.id=function:effect_track.is_idle
scope.6.kind=function
scope.6.startLine=64
scope.6.endLine=66
scope.6.semanticHash=3326e00002fe0b9a
scope.7.id=function:effect_track.await_all
scope.7.kind=function
scope.7.startLine=68
scope.7.endLine=87
scope.7.semanticHash=b38abe71ae04f09a
scope.8.id=function:_poll
scope.8.kind=function
scope.8.startLine=76
scope.8.endLine=84
scope.8.semanticHash=f64bff92c55d8042
scope.9.id=function:_pressure
scope.9.kind=function
scope.9.startLine=89
scope.9.endLine=101
scope.9.semanticHash=8063df313731c4dd
scope.10.id=function:effect_track.scaled_duration
scope.10.kind=function
scope.10.startLine=110
scope.10.endLine=120
scope.10.semanticHash=42bc60c79068e812
scope.11.id=function:_merge_amount
scope.11.kind=function
scope.11.startLine=122
scope.11.endLine=126
scope.11.semanticHash=b475d99b1e0545ae
scope.12.id=function:_merge_sum_run
scope.12.kind=function
scope.12.startLine=130
scope.12.endLine=145
scope.12.semanticHash=d6d7c287f9698902
scope.13.id=function:_can_coalesce
scope.13.kind=function
scope.13.startLine=147
scope.13.endLine=149
scope.13.semanticHash=99d5f926c9946ecf
scope.14.id=function:effect_track.coalesce_queue
scope.14.kind=function
scope.14.startLine=151
scope.14.endLine=174
scope.14.semanticHash=31d0ddd3f8399e82
scope.15.id=function:effect_track.reset
scope.15.kind=function
scope.15.startLine=176
scope.15.endLine=179
scope.15.semanticHash=23c1f371051bafed
]]
