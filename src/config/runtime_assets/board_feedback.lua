local number_utils = require("src.foundation.number")
local state = require("src.config.runtime_assets.state")
local results = require("src.config.runtime_assets.results")

local M = {}

local function _warn_invalid_number(cue_name, field, value, reason)
  local logger = require("src.foundation.log")
  logger.warn(
    "board_feedback",
    "invalid cue config",
    "cue_name=" .. tostring(cue_name),
    "field=" .. tostring(field),
    "value=" .. tostring(value),
    "reason=" .. tostring(reason)
  )
end

local function _resolve_numeric_field(cue_name, field, value)
  if value == nil then
    return nil
  end
  if number_utils.is_numeric(value) then
    -- 保整数类型的数值归一(int*1=int,float*1=float);`value + 0` 的
    -- + -> - 逐值等价不可杀,`* 1` 形态下 * -> / 会产生 float 类型分歧(#261)。
    return value * 1
  end
  local reason = type(value) == "table" and "vector_like_not_allowed" or "non_numeric"
  _warn_invalid_number(cue_name, field, value, reason)
  return nil
end

local function _cue_value(cue, payload, field)
  if type(payload) == "table" and payload[field] ~= nil then
    return payload[field]
  end
  return cue and cue[field] or nil
end

local function _cue_numeric(cue_name, cue, payload, field)
  return _resolve_numeric_field(cue_name, field, _cue_value(cue, payload, field))
end

-- kind 到资产表名的映射:effect → effects,其余一律 audio。
local function _ref_table_name(kind)
  return kind == "effect" and "effects" or "audio"
end

function M.resolve_asset_ref(refs, kind, ref_name)
  if type(ref_name) ~= "string" or ref_name == "" then
    return nil
  end
  local table_name = _ref_table_name(kind)
  return number_utils.to_integer((refs[table_name] or {})[ref_name])
end

local function _cue_asset_id(refs, cue, payload, kind)
  local explicit = number_utils.to_integer(type(payload) == "table" and payload[kind .. "_id"] or nil)
  if explicit ~= nil then
    return explicit
  end
  local ref_name = _cue_value(cue, payload, kind .. "_id_ref")
  return M.resolve_asset_ref(refs, kind, ref_name), ref_name
end

local function _resolve_bind_offset(value, constants)
  if type(value) == "string" then
    return constants[value]
  end
  return value
end

local function _followup_sound(refs, cue_name, entry)
  if type(entry) ~= "table" then
    return nil
  end
  local explicit = number_utils.to_integer(entry.sound_id)
  local sound_id = explicit or M.resolve_asset_ref(refs, "sound", entry.sound_id_ref)
  return {
    cue_name = cue_name,
    sound_id = sound_id,
    sound_id_ref = entry.sound_id_ref,
    delay = _resolve_numeric_field(cue_name, "followup_sounds.delay", entry.delay),
    duration = _resolve_numeric_field(cue_name, "followup_sounds.duration", entry.duration),
    volume = _resolve_numeric_field(cue_name, "followup_sounds.volume", entry.volume),
  }
end

local function _followup_entries(cue, payload)
  if type(payload) == "table" and payload.followup_sounds ~= nil then
    return payload.followup_sounds
  end
  return cue and cue.followup_sounds or nil
end

local function _followup_sounds(refs, cue_name, cue, payload)
  local entries = _followup_entries(cue, payload)
  if type(entries) ~= "table" then
    return nil
  end
  local out = {}
  for _, entry in ipairs(entries) do
    local resolved = _followup_sound(refs, cue_name, entry)
    if resolved ~= nil then
      out[#out + 1] = resolved
    end
  end
  return out
end

function M.board_feedback_cue(cue_name, payload, opts)
  local refs = state.refs(opts)
  local cue = type(cue_name) == "string" and (refs.board_feedback or {})[cue_name] or nil
  if cue == nil then
    return results.missing("board_feedback.cue", "missing_board_feedback_cue", {
      cue_name = cue_name,
    })
  end
  return results.result("board_feedback.cue", {
    cue_name = cue_name,
    effect_id = _cue_asset_id(refs, cue, payload, "effect"),
    effect_lookup_key = _cue_value(cue, payload, "effect_id_ref"),
    sound_id = _cue_asset_id(refs, cue, payload, "sound"),
    sound_lookup_key = _cue_value(cue, payload, "sound_id_ref"),
    scale = _cue_numeric(cue_name, cue, payload, "scale"),
    rate = _cue_numeric(cue_name, cue, payload, "rate"),
    duration = _cue_numeric(cue_name, cue, payload, "duration"),
    volume = _cue_numeric(cue_name, cue, payload, "volume"),
    delay = _cue_numeric(cue_name, cue, payload, "delay"),
    sound_duration = _cue_numeric(cue_name, cue, payload, "sound_duration"),
    rot = _cue_value(cue, payload, "rot"),
    with_sound = _cue_value(cue, payload, "with_sound"),
    bind_to_player = cue.bind_to_player,
    bind_type = cue.bind_type,
    socket_name = cue.socket_name,
    bind_offset = _resolve_bind_offset(_cue_value(cue, payload, "bind_offset"), state.constants()),
    allow_missing = cue.allow_missing_resource == true,
    followup_sounds = _followup_sounds(refs, cue_name, cue, payload),
  })
end

return M

