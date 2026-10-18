local number_utils = require("src.foundation.number")
local state = require("src.config.runtime_assets.state")
local results = require("src.config.runtime_assets.results")
local images = require("src.config.runtime_assets.images")

local M = {}

local function _synthetic_name(slot_index, cfg)
  local names = cfg.names or {}
  return names[slot_index] or ("AI" .. tostring(slot_index))
end

local function _synthetic_unit_key(slot, cfg, opts)
  local unit_key = type(opts) == "table" and opts.unit_key or nil
  if unit_key == nil then
    unit_key = (cfg.unit_keys or {})[slot]
  end
  return unit_key
end

local function _synthetic_avatar(slot, opts)
  local avatar = images.image_for_chance_card("AI" .. tostring(slot), opts)
  if avatar.ok == true then
    return avatar, false, nil
  end
  return images.empty_image(opts), true, "missing_synthetic_ai_avatar"
end

function M.synthetic_ai_profile(slot_index, opts)
  local slot = number_utils.to_integer(slot_index) or 1
  local refs = state.refs(opts)
  local cfg = refs.synthetic_ai or {}
  local avatar, fallback_used, reason = _synthetic_avatar(slot, opts)
  return results.result("synthetic_ai.profile", {
    slot_index = slot,
    name = _synthetic_name(slot, cfg),
    unit_key = _synthetic_unit_key(slot, cfg, opts),
    avatar_image_key = avatar.image_key,
    avatar_result = avatar,
    fallback_used = fallback_used,
    reason = reason,
  })
end

function M.synthetic_ai_unit_key_pool(opts)
  local refs = state.refs(opts)
  local unit_keys = ((refs.synthetic_ai or {}).unit_keys) or {}
  local out = {}
  for index, unit_key in ipairs(unit_keys) do
    out[index] = unit_key
  end
  return out
end

return M

