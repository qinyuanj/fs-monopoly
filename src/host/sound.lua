local logger = require("src.foundation.log")
local number_utils = require("src.foundation.number")
local runtime_constants = require("src.config.gameplay.runtime_constants")

local sfx_runtime = {}
local default_sfx_duration = 1.0
local default_sfx_rate = 1.0
local default_with_sound = false
local default_sound_duration = 1.0
local default_sound_volume = 1.0

local function _warn_skip(...)
  logger.warn("board_feedback", ...)
end

local _resolve_numeric = number_utils.resolve_numeric

local function _has_named_component(value)
  return value.x ~= nil or value.y ~= nil or value.z ~= nil
end

local function _has_indexed_component(value)
  return value[1] ~= nil or value[2] ~= nil or value[3] ~= nil
end

local function _is_vector_like(value)
  if type(value) ~= "table" then
    return false
  end
  return _has_named_component(value) or _has_indexed_component(value)
end

local function _resolve_rotation(rot)
  if rot ~= nil then
    return rot
  end
  return runtime_constants.q_zero
end

local function _resolve_pos(pos)
  if pos ~= nil then
    return pos
  end
  return runtime_constants.v3_zero
end

local function _invalid_positive_integer_id(value)
  local resolved = number_utils.to_integer(value)
  return resolved == nil or resolved <= 0, resolved
end

local function _scale_invalid(scale, resolved_scale)
  return resolved_scale == nil or _is_vector_like(scale)
end

local function _resolve_sfx_params(sfx_key, scale, duration, rate, pos, rot, cue_name)
  local invalid_key, resolved_sfx_key = _invalid_positive_integer_id(sfx_key)
  if invalid_key then
    _warn_skip("skip play_sfx_by_key: invalid sfx_key", "cue_name=" .. tostring(cue_name), "sfx_key=" .. tostring(sfx_key))
    return nil
  end
  local resolved_scale = _resolve_numeric(scale, 1.0)
  if _scale_invalid(scale, resolved_scale) then
    _warn_skip(
      "skip play_sfx_by_key: invalid scale",
      "cue_name=" .. tostring(cue_name),
      "sfx_key=" .. tostring(resolved_sfx_key),
      "scale=" .. tostring(scale),
      "rate=" .. tostring(rate)
    )
    return nil
  end
  local resolved_rate = _resolve_numeric(rate, default_sfx_rate)
  if resolved_rate == nil then
    _warn_skip(
      "skip play_sfx_by_key: invalid rate",
      "cue_name=" .. tostring(cue_name),
      "sfx_key=" .. tostring(resolved_sfx_key),
      "scale=" .. tostring(resolved_scale),
      "rate=" .. tostring(rate)
    )
    return nil
  end
  return {
    sfx_key = resolved_sfx_key,
    scale = resolved_scale,
    duration = _resolve_numeric(duration, default_sfx_duration),
    rate = resolved_rate,
    pos = _resolve_pos(pos),
    rot = _resolve_rotation(rot),
  }
end

local function _with_sound_flag(with_sound)
  return with_sound == true or default_with_sound
end

local function _game_api_with(method_name)
  local game_api = GameAPI
  if game_api and type(game_api[method_name]) == "function" then
    return game_api
  end
  return nil
end

local function _play_sfx_call(game_api, params, resolved_with_sound)
  return pcall(
    game_api.play_sfx_by_key,
    params.sfx_key,
    params.pos,
    params.rot,
    params.scale,
    params.duration,
    params.rate,
    resolved_with_sound
  )
end

function sfx_runtime.play_sfx_by_key(sfx_key, pos, rot, scale, duration, rate, with_sound, opts)
  opts = opts or {}
  local params = _resolve_sfx_params(sfx_key, scale, duration, rate, pos, rot, opts.cue_name)
  if not params then
    return nil
  end
  local resolved_with_sound = _with_sound_flag(with_sound)
  local game_api = _game_api_with("play_sfx_by_key")
  if game_api == nil then
    _warn_skip("skip play_sfx_by_key: missing GameAPI.play_sfx_by_key")
    return nil
  end
  local ok, sfx_id = _play_sfx_call(game_api, params, resolved_with_sound)
  if not ok then
    _warn_skip(
      "play_sfx_by_key failed:",
      "cue_name=" .. tostring(opts.cue_name),
      "sfx_key=" .. tostring(params.sfx_key),
      "scale=" .. tostring(params.scale),
      "duration=" .. tostring(params.duration),
      "rate=" .. tostring(params.rate),
      "with_sound=" .. tostring(resolved_with_sound)
    )
    return nil
  end
  return sfx_id
end

function sfx_runtime.play_3d_sound(pos, sound_id, duration, volume)
  local invalid, resolved_sound_id = _invalid_positive_integer_id(sound_id)
  if invalid then
    _warn_skip("skip play_3d_sound: invalid sound_id", tostring(sound_id))
    return nil
  end
  local game_api = _game_api_with("play_3d_sound")
  if game_api == nil then
    _warn_skip("skip play_3d_sound: missing GameAPI.play_3d_sound")
    return nil
  end
  local resolved_pos = _resolve_pos(pos)
  local resolved_duration = _resolve_numeric(duration, default_sound_duration)
  local resolved_volume = _resolve_numeric(volume, default_sound_volume)
  local ok, assigned_sound_id = pcall(game_api.play_3d_sound, resolved_pos, resolved_sound_id, resolved_duration, resolved_volume)
  if not ok then
    _warn_skip("play_3d_sound failed:", tostring(resolved_sound_id))
    return nil
  end
  return assigned_sound_id
end

function sfx_runtime.bind_sfx_to_unit(sfx_id, unit, socket_name, pos, bind_type)
  if sfx_id == nil or unit == nil then
    return false
  end
  local global_api = GlobalAPI
  if not (global_api and type(global_api.bind_sfx_to_unit) == "function") then
    return false
  end
  local ok = pcall(global_api.bind_sfx_to_unit, sfx_id, unit, socket_name, pos, bind_type)
  return ok
end

return sfx_runtime

