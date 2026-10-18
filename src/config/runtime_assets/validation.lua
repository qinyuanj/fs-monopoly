local state = require("src.config.runtime_assets.state")
local images = require("src.config.runtime_assets.images")
local board_feedback = require("src.config.runtime_assets.board_feedback")

local M = {}

local function _add_error(errors, reason, message, fields)
  local entry = fields
  entry.reason = reason
  entry.message = message
  errors[#errors + 1] = entry
end

local function _validate_startup_item_icons(errors, refs)
  for slot in ipairs(state.startup_item_ids()) do
    local icon = images.startup_item_slot_icon(slot, { refs = refs })
    if icon.ok ~= true then
      _add_error(errors, "missing_startup_item_icon", "missing startup item icon: " .. tostring(icon.lookup_key), {
        lookup_key = icon.lookup_key,
        slot_index = slot,
      })
    end
  end
end

local function _skin_product_id(skin)
  return skin and skin.product_id or nil
end

local function _validate_skin_card(errors, refs, product_id)
  local card = images.image_for_skin_card(product_id, { refs = refs })
  if card.ok ~= true then
    _add_error(errors, "missing_skin_card_image", "missing skin card image: " .. tostring(product_id), {
      product_id = product_id,
    })
  end
end

local function _validate_skin_model(errors, refs, product_id)
  local model = images.skin_model_for_product(product_id, { refs = refs })
  if model.ok ~= true then
    _add_error(errors, "missing_skin_model", "missing skin model: " .. tostring(product_id), {
      product_id = product_id,
    })
  end
end

local function _validate_skins(errors, refs)
  for _, skin in ipairs(state.skins() or {}) do
    local product_id = _skin_product_id(skin)
    _validate_skin_card(errors, refs, product_id)
    _validate_skin_model(errors, refs, product_id)
  end
end

local function _validate_cue_ref(errors, refs, cue_name, ref, kind, reason, label)
  if ref == nil then
    return
  end
  if board_feedback.resolve_asset_ref(refs, kind, ref) ~= nil then
    return
  end
  _add_error(
    errors,
    reason,
    "board feedback " .. label .. " references unknown " .. kind .. "_id_ref: " .. tostring(ref) .. " (cue_name=" .. tostring(cue_name) .. ")",
    { cue_name = cue_name, ref = ref }
  )
end

local function _validate_followup_sound(errors, refs, cue_name, entry)
  local followup_ref = entry and entry.sound_id_ref or nil
  _validate_cue_ref(
    errors,
    refs,
    cue_name,
    followup_ref,
    "sound",
    "missing_board_feedback_followup_sound",
    "followup"
  )
end

local function _validate_board_feedback(errors, refs)
  for cue_name, cue in pairs(refs.board_feedback or {}) do
    _validate_cue_ref(errors, refs, cue_name, cue.effect_id_ref, "effect", "missing_board_feedback_effect", "cue")
    _validate_cue_ref(errors, refs, cue_name, cue.sound_id_ref, "sound", "missing_board_feedback_sound", "cue")
    for _, entry in ipairs(cue.followup_sounds or {}) do
      _validate_followup_sound(errors, refs, cue_name, entry)
    end
  end
end

function M.validate_catalog(opts)
  local refs = state.refs(opts)
  local errors = {}
  _validate_board_feedback(errors, refs)
  _validate_skins(errors, refs)
  _validate_startup_item_icons(errors, refs)
  return {
    ok = #errors == 0,
    errors = errors,
  }
end

return M

