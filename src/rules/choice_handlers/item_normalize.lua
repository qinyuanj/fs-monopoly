local availability = require("src.rules.items.availability")
local item_phase = require("src.rules.items.phase")

local copy_table = availability.copy_table
local normalize_integer_field = availability.normalize_integer_field

local normalize = {}

normalize.copy_table = copy_table
normalize.normalize_integer_field = normalize_integer_field

function normalize.choice_action_option_id(choice_kind, action)
  local normalized_action = copy_table(action)
  normalize_integer_field(normalized_action, "option_id", choice_kind, "action", true)
  return normalized_action
end

function normalize.validate_item_player(game, choice_kind, meta)
  return assert(game:find_player_by_id(meta.player_id), "missing player: " .. tostring(meta.player_id))
end

function normalize.is_repeatable_phase_meta(meta)
  return type(meta) == "table" and item_phase.is_repeatable(meta.phase)
end

function normalize.merge_after_action_anim(result, final_res)
  if type(result) == "table" and type(result.after_action_anim) == "table" then
    final_res.after_action_anim = result.after_action_anim
  end
  return final_res
end

function normalize.owner_meta(choice_kind, meta, choice_spec)
  local normalized_meta = copy_table(meta)
  normalize_integer_field(normalized_meta, "player_id", choice_kind)
  choice_spec.owner_role_id = choice_spec.owner_role_id or normalized_meta.player_id
  return normalized_meta
end

function normalize.item_phase_meta(_, meta, choice_spec)
  local normalized_meta = normalize.owner_meta(choice_spec.kind, meta, choice_spec)
  assert(type(normalized_meta.phase) == "string" and normalized_meta.phase ~= "",
    tostring(choice_spec.kind) .. " requires string meta.phase")
  return normalized_meta
end

function normalize.validate_item_phase_meta(game, meta, choice_spec)
  normalize.validate_item_player(game, choice_spec.kind, meta)
  assert(item_phase.is_enabled(meta.phase), tostring(choice_spec.kind) .. " requires enabled meta.phase")
end

function normalize.validate_item_owner_meta(game, meta, choice_spec)
  normalize.validate_item_player(game, choice_spec.kind, meta)
end

function normalize.item_target_meta(_, meta, choice_spec)
  local normalized_meta = normalize.owner_meta(choice_spec.kind, meta, choice_spec)
  normalize_integer_field(normalized_meta, "item_id", choice_spec.kind)
  return normalized_meta
end

function normalize.remote_dice_meta(_, meta, choice_spec)
  local normalized_meta = normalize.item_target_meta(nil, meta, choice_spec)
  normalize_integer_field(normalized_meta, "dice_count", choice_spec.kind)
  return normalized_meta
end

function normalize.validate_remote_dice_meta(game, meta, choice_spec)
  normalize.validate_item_owner_meta(game, meta, choice_spec)
  if meta.dice_count ~= nil then
    assert(meta.dice_count >= 1, tostring(choice_spec.kind) .. " requires positive meta.dice_count")
  end
end

return normalize

