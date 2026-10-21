local actions = require("src.app.cosmetics.transaction_actions")
local transaction_context = require("src.app.cosmetics.transaction_context")

local transaction = {}

local function _sync_catalog()
  transaction.catalog = transaction_context.catalog()
end

function transaction.handle_skin_transaction(state, role_id, request)
  return actions.handle_skin_transaction(state, role_id, request)
end

function transaction.complete_skin_purchase(state, role_id, product_id)
  return actions.complete_skin_purchase(state, role_id, product_id)
end

function transaction.restore_role(state, role_id)
  return actions.restore_role(state, role_id)
end

function transaction.is_slot_equipped(state, slot_index)
  return actions.is_slot_equipped(state, slot_index)
end

function transaction.slot_view_model(state, slot_index)
  return actions.slot_view_model(state, slot_index)
end

function transaction.slot_view_models(state, catalog)
  return actions.slot_view_models(state, catalog)
end

function transaction.equipped_product(state, role_id)
  return actions.equipped_product(state, role_id)
end

function transaction.configure_equip(callback)
  transaction_context.configure_equip(callback)
end

function transaction.configure_unequip(callback)
  transaction_context.configure_unequip(callback)
end

function transaction.configure_transaction_result_applier(callback)
  transaction_context.configure_transaction_result_applier(callback)
end

function transaction.configure_archive(archive)
  transaction_context.configure_archive(archive)
end

function transaction.configure_catalog_for_tests(new_catalog)
  transaction_context.configure_catalog_for_tests(new_catalog)
  _sync_catalog()
end

-- #513：公开重新排序入口，供面板在 open 前刷新 catalog 快照（panel.sync_catalog 调用）。
function transaction.refresh_catalog()
  _sync_catalog()
end

function transaction.reset_for_tests()
  transaction_context.reset_for_tests()
  _sync_catalog()
end

_sync_catalog()

return transaction

