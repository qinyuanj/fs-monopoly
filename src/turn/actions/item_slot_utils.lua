local number_utils = require("src.foundation.number")

local item_slot_utils = {}

function item_slot_utils.resolve_slot_index(slot_index_or_id)
  if number_utils.is_numeric(slot_index_or_id) then
    return number_utils.to_integer(slot_index_or_id)
  end
  if type(slot_index_or_id) ~= "string" then
    return nil
  end
  local matched = string.match(slot_index_or_id, "^item_slot_(%d+)$")
  if matched == nil then
    return nil
  end
  return number_utils.to_integer(matched)
end

return item_slot_utils

