local runtime_constants = require("src.config.gameplay.runtime_constants")
local effect_track = require("src.ui.render.support.effect_track")
local cue_refs = require("src.ui.render.board_feedback.cue_refs")
local host_runtime_guard = require("src.ui.render.board_feedback.host_runtime")

local M = {}

local default_sfx_scale = 1.0
local default_sfx_rate = 1.0
local default_sfx_duration = 1.0
local default_with_sound = false

local function _resolve_with_sound(cue, payload)
  local with_sound = payload and payload.with_sound
  if with_sound == nil then
    with_sound = cue.with_sound
  end
  if with_sound == nil then
    with_sound = default_with_sound
  end
  return with_sound
end

local function _effect_duration(cue, payload)
  local raw_duration = cue_refs.resolve_numeric(payload and payload.duration or cue.duration, default_sfx_duration)
  return effect_track.scaled_duration(raw_duration)
end

local function _effect_scale(cue_name, cue, payload)
  return cue_refs.resolve_sfx_scale(cue_name, payload and payload.scale or cue.scale, default_sfx_scale)
end

local function _effect_rot(cue, payload)
  return payload and payload.rot or cue.rot or runtime_constants.q_zero
end

local function _effect_rate(cue, payload)
  return cue_refs.resolve_numeric(payload and payload.rate or cue.rate, default_sfx_rate)
end

local function _resolve_effect_params(cue_name, cue, payload)
  local effect_id = cue_refs.resolve_cue_ref_id(cue_name, cue, payload, "effect")
  if effect_id == nil then
    return nil
  end
  return {
    effect_id = effect_id,
    duration = _effect_duration(cue, payload),
    scale = _effect_scale(cue_name, cue, payload),
    rot = _effect_rot(cue, payload),
    rate = _effect_rate(cue, payload),
    with_sound = _resolve_with_sound(cue, payload),
  }
end

local function _play_sfx(host_runtime, cue_name, pos, params)
  return host_runtime.play_sfx_by_key(params.effect_id, pos, params.rot, params.scale, params.duration, params.rate, params.with_sound, {
    cue_name = cue_name,
  })
end

local function _bind_sfx_to_player(host_runtime, cue, sfx_id, unit)
  if cue.bind_to_player ~= true or unit == nil then
    return
  end
  if type(host_runtime.bind_sfx_to_unit) ~= "function" then
    return
  end
  host_runtime.bind_sfx_to_unit(
    sfx_id,
    unit,
    cue.socket_name,
    cue.bind_offset or runtime_constants.v3_one,
    cue.bind_type
  )
end

function M.play(cue_name, cue, pos, unit, payload, host_runtime)
  local params = _resolve_effect_params(cue_name, cue, payload)
  if params == nil then
    return false
  end
  host_runtime = host_runtime_guard.with_method(host_runtime, "play_sfx_by_key")
  if host_runtime == nil then
    return false
  end
  local sfx_id = _play_sfx(host_runtime, cue_name, pos, params)
  if sfx_id == nil then
    return false
  end
  effect_track.spawn(cue_name, "effect", params.duration)
  _bind_sfx_to_player(host_runtime, cue, sfx_id, unit)
  return true
end

return M

