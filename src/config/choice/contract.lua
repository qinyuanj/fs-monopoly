local number_utils = require("src.foundation.number")

local choice_contract = {}

local function _resolve_role_id_field(choice, field_key)
  if type(choice) ~= "table" then
    return nil
  end
  return number_utils.to_integer(choice[field_key])
end

-- Handler-specific payload like phase, queue, effect_ids, and move_result stays in meta.
choice_contract.explicit_fields = {
  "route_key",
  "requires_confirm",
  "pre_confirm_on_select",
  "owner_role_id",
  "confirm_title",
  "confirm_body",
  "uses_item_slots",
  "pre_confirm_before_slot_pick",
  "target_slot_layout",
  "active_tab",
  "page_index",
  "page_count",
}

function choice_contract.copy_explicit_fields(source, target)
  assert(type(target) == "table", "missing target")
  if type(source) ~= "table" then
    return target
  end
  for _, key in ipairs(choice_contract.explicit_fields) do
    target[key] = source[key]
  end
  return target
end

function choice_contract.resolve_owner_role_id(choice)
  return _resolve_role_id_field(choice, "owner_role_id")
end

local function _resolve_meta_player_role_id(choice)
  local meta = type(choice) == "table" and choice.meta or nil
  if type(meta) ~= "table" then
    return nil
  end
  return number_utils.to_integer(meta.player_id)
end

function choice_contract.resolve_owner_or_meta_role_id(choice)
  local owner_role_id = choice_contract.resolve_owner_role_id(choice)
  if owner_role_id ~= nil then
    return owner_role_id
  end
  return _resolve_meta_player_role_id(choice)
end

return choice_contract

