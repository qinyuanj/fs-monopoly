local transaction_context = require("src.app.cosmetics.transaction_context")
local transaction_state = require("src.app.cosmetics.transaction_state")

local result = {}

function result.panel_or_rejection(root_state)
  local panel, err = transaction_state.ensure_panel(root_state)
  if panel == nil then
    return nil, transaction_state.rejected(nil, err)
  end
  return panel, nil
end

function result.value_or_rejection(panel, value, reason)
  if value == nil then
    return nil, transaction_state.rejected(panel, reason)
  end
  return value, nil
end

local function _equipped_skin_fields(fields, skin, applied)
  fields.equipped_product = skin.product_id
  fields.panel_should_close = true
  fields.slot_view_dirty = true
  fields.host_action_attempted = transaction_context.has_equip_adapter()
  fields.host_action_result = applied
  fields.notification = "已换装 " .. tostring(skin.name)
  return fields
end

function result.accepted_equipped_skin(panel, role_id, skin, fields)
  local applied = transaction_state.apply_equip(panel, role_id, skin)
  panel.open = false
  return transaction_state.accepted(panel, _equipped_skin_fields(fields, skin, applied))
end

return result

