local transaction_state = require("src.app.cosmetics.transaction_state")

local queries = {}

local function _skin_panel(root_state)
  return root_state and root_state.ui and root_state.ui.skin_panel or nil
end

function queries.is_slot_equipped(root_state, slot_index)
  local panel = _skin_panel(root_state)
  if panel == nil or panel.role_id == nil then
    return false
  end
  local skin = transaction_state.skin_at(panel, slot_index)
  if skin == nil then
    return false
  end
  return transaction_state.equipped_product(panel, panel.role_id) == skin.product_id
end

-- role_id 兜底只住 read_model 一处(`role_id or (panel and panel.role_id)`,
-- transaction_state 直连 read_model):这里再写 `panel.role_id or nil` 是冗余
-- 兜底,or→and 变异观测等价(#293 等价变异体,删冗余源码处置)。
function queries.slot_view_model(root_state, slot_index, catalog)
  local panel = _skin_panel(root_state)
  return transaction_state.slot_view_model(panel, nil, slot_index, catalog)
end

function queries.slot_view_models(root_state, catalog)
  local panel = _skin_panel(root_state)
  return transaction_state.slot_view_models(panel, nil, catalog)
end

function queries.equipped_product(root_state, role_id)
  local panel = _skin_panel(root_state)
  return transaction_state.equipped_product(panel, role_id)
end

return queries

