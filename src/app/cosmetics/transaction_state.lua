local transaction_context = require("src.app.cosmetics.transaction_context")
local read_model = require("src.app.cosmetics.transaction_read_model")

local state = {}

-- Catalog indexing and slot view-model projections live in
-- transaction_read_model; re-exported here so the transaction_state API stays
-- unchanged for existing callers.
state.role_key = read_model.role_key
state.slot_index = read_model.slot_index
state.skin_at = read_model.skin_at
state.skin_by_product = read_model.skin_by_product
state.clamp_page = read_model.clamp_page
state.slot_view_model = read_model.slot_view_model
state.slot_view_models = read_model.slot_view_models

local function _new_panel()
  return {
    open = false,
    page_index = 1,
    owned_by_role = {},
    selected_by_role = {},
  }
end

local function _ensure_panel_tables(panel)
  panel.owned_by_role = panel.owned_by_role or {}
  panel.selected_by_role = panel.selected_by_role or {}
  panel.pending_skin_purchase_by_role = panel.pending_skin_purchase_by_role or {}
end

function state.ensure_panel(root_state)
  local ui = root_state and root_state.ui or nil
  if ui == nil then
    return nil, "missing_state"
  end
  ui.skin_panel = ui.skin_panel or _new_panel()
  local panel = ui.skin_panel
  _ensure_panel_tables(panel)
  return panel, nil
end

function state.accepted(panel, fields)
  local result = fields or {}
  result.accepted = true
  result.ok = true
  result.panel = panel
  return result
end

function state.rejected(panel, reason, fields)
  local result = fields or {}
  result.accepted = false
  result.ok = false
  result.reason = reason
  result.panel = panel
  return result
end

local function _owned_bucket(panel, key)
  panel.owned_by_role[key] = panel.owned_by_role[key] or {}
  return panel.owned_by_role[key]
end

function state.mark_owned(panel, role_id, skin, source)
  local key = state.role_key(role_id)
  if key == nil or skin == nil then
    return false
  end
  _owned_bucket(panel, key)[skin.product_id] = true
  if source == "purchase" then
    transaction_context.archive_call("mark_owned", role_id, skin.product_id)
  end
  return true
end

local function _load_owned_list(bucket, owned)
  for _, product_id in ipairs(owned) do
    bucket[product_id] = true
  end
end

local function _load_owned_map(bucket, owned)
  for product_id, is_owned in pairs(owned) do
    if is_owned == true then
      bucket[product_id] = true
    end
  end
end

function state.load_owned(panel, role_id)
  local key = state.role_key(role_id)
  if key == nil then
    return
  end
  local owned = transaction_context.archive_call("load_owned", role_id)
  if type(owned) ~= "table" then
    return
  end
  local bucket = _owned_bucket(panel, key)
  _load_owned_list(bucket, owned)
  _load_owned_map(bucket, owned)
end

function state.owns_skin(panel, role_id, skin)
  local key = state.role_key(role_id)
  local bucket = key and panel.owned_by_role[key] or nil
  return bucket ~= nil and skin ~= nil and bucket[skin.product_id] == true
end

local function _effective_role_id(panel, role_id)
  return role_id or (panel and panel.role_id)
end

function state.equipped_product(panel, role_id)
  local key = state.role_key(_effective_role_id(panel, role_id))
  if key == nil or panel == nil or panel.selected_by_role == nil then
    return nil
  end
  return panel.selected_by_role[key]
end

function state.apply_equip(panel, role_id, skin)
  local key = state.role_key(role_id)
  if key == nil then
    return false
  end
  local applied = transaction_context.call_equip_adapter(role_id, skin)
  panel.last_equip_ok_by_role = panel.last_equip_ok_by_role or {}
  panel.last_equip_ok_by_role[key] = applied
  panel.selected_by_role[key] = skin.product_id
  transaction_context.archive_call("save_equipped", role_id, skin.product_id)
  return applied
end

function state.apply_unequip(panel, role_id)
  local key = state.role_key(role_id)
  if key == nil then
    return false
  end
  panel.selected_by_role[key] = nil
  transaction_context.archive_call("save_equipped", role_id, nil)
  transaction_context.call_unequip_adapter(role_id)
  return true
end

local function _needs_seed(panel, key)
  return key ~= nil and panel.selected_by_role[key] == nil
end

function state.seed_equipped(panel, role_id)
  local key = state.role_key(role_id)
  if not _needs_seed(panel, key) then
    return nil
  end
  local product_id = transaction_context.archive_call("load_equipped", role_id)
  if product_id == nil then
    return nil
  end
  local skin = state.skin_by_product(product_id)
  if skin == nil or not state.owns_skin(panel, role_id, skin) then
    return nil
  end
  state.apply_equip(panel, role_id, skin)
  return skin.product_id
end

return state

