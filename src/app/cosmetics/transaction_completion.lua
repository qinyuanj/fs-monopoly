local purchase = require("src.app.cosmetics.transaction_purchase")
local transaction_result = require("src.app.cosmetics.transaction_result")
local transaction_state = require("src.app.cosmetics.transaction_state")

local completion = {}

local function _pending_or_rejection(panel, role_id, product_id)
  local key = transaction_state.role_key(role_id)
  local pending = key and panel.pending_skin_purchase_by_role[key] or nil
  if pending == nil then
    return nil, transaction_state.rejected(panel, "pending_purchase_missing")
  end
  if pending.product_id ~= product_id then
    return nil, transaction_state.rejected(panel, "pending_purchase_mismatch")
  end
  return pending, nil
end

local function _product_or_rejection(panel, product_id)
  return transaction_result.value_or_rejection(panel, transaction_state.skin_by_product(product_id), "missing_product")
end

local function _accepted_purchase_complete(panel, role_id, skin)
  return transaction_result.accepted_equipped_skin(panel, role_id, skin, {
    action = "purchase_complete",
    purchase_fulfilled = true,
    ownership_changed = true,
  })
end

function completion.complete_skin_purchase(root_state, role_id, product_id)
  local panel, rejected = transaction_result.panel_or_rejection(root_state)
  if rejected ~= nil then
    return rejected
  end
  local _, pending_rejected = _pending_or_rejection(panel, role_id, product_id)
  if pending_rejected ~= nil then
    return pending_rejected
  end
  local skin, product_rejected = _product_or_rejection(panel, product_id)
  if product_rejected ~= nil then
    return product_rejected
  end
  purchase.clear_pending(panel, role_id)
  transaction_state.mark_owned(panel, role_id, skin)
  return _accepted_purchase_complete(panel, role_id, skin)
end

return completion

