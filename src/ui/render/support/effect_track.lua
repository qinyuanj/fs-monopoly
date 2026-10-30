local runtime_ports = require("src.foundation.ports.runtime_ports")
local tables = require("src.foundation.tables")

local effect_track = {}

local active_tokens = {}
local next_token_id = 1
local timeout_seconds = 10.0

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
  return tables.count(active_tokens) == 0
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
  local count = tables.count(active_tokens)
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

