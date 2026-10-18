local purchase = require("src.app.cosmetics.transaction_purchase")
local completion = require("src.app.cosmetics.transaction_completion")
local transaction_context = require("src.app.cosmetics.transaction_context")
local transaction_result = require("src.app.cosmetics.transaction_result")
local transaction_state = require("src.app.cosmetics.transaction_state")
local request_shape = require("src.ui.schema.skin_request")
local queries = require("src.app.cosmetics.transaction_queries")

local actions = {}

local function _skin_or_rejection(panel, slot_index)
  return transaction_result.value_or_rejection(panel, transaction_state.skin_at(panel, slot_index), "missing_skin")
end

local function _open(root_state, role_id)
  local panel, rejected = transaction_result.panel_or_rejection(root_state)
  if rejected ~= nil then
    return rejected
  end
  panel.open = true
  panel.role_id = role_id
  panel.page_index = 1
  transaction_state.load_owned(panel, role_id)
  local equipped_product = transaction_state.seed_equipped(panel, role_id)
  return transaction_state.accepted(panel, {
    action = "open",
    slot_view_dirty = true,
    equipped_product = equipped_product,
    notification = "皮肤已打开",
  })
end

local function _page_delta(root_state, delta)
  local panel, rejected = transaction_result.panel_or_rejection(root_state)
  if rejected ~= nil then
    return rejected
  end
  panel.page_index = transaction_state.clamp_page((panel.page_index or 1) + delta)
  return transaction_state.accepted(panel, {
    action = "page",
    slot_view_dirty = true,
  })
end

local function _close(root_state, role_id)
  local panel, rejected = transaction_result.panel_or_rejection(root_state)
  if rejected ~= nil then
    return rejected
  end
  panel.open = false
  return transaction_state.accepted(panel, {
    action = "close",
    panel_should_close = true,
    role_id = role_id or panel.role_id,
    notification = "已关闭",
  })
end

local function _accepted_equip(panel, role_id, skin)
  return transaction_result.accepted_equipped_skin(panel, role_id, skin, {
    action = "equip",
  })
end

local function _equip_slot(root_state, role_id, slot_index)
  local panel, rejected = transaction_result.panel_or_rejection(root_state)
  if rejected ~= nil then
    return rejected
  end
  role_id = role_id or panel.role_id
  local skin, skin_rejected = _skin_or_rejection(panel, slot_index)
  if skin_rejected ~= nil then
    return skin_rejected
  end
  if not transaction_state.owns_skin(panel, role_id, skin) then
    return purchase.start(root_state, panel, role_id, skin, actions.complete_skin_purchase)
  end
  return _accepted_equip(panel, role_id, skin)
end

local function _unlock_slot(root_state, role_id, slot_index, source)
  local panel, rejected = transaction_result.panel_or_rejection(root_state)
  if rejected ~= nil then
    return rejected
  end
  role_id = role_id or panel.role_id
  local skin, skin_rejected = _skin_or_rejection(panel, slot_index)
  if skin_rejected ~= nil then
    return skin_rejected
  end
  transaction_state.mark_owned(panel, role_id, skin, source)
  return transaction_state.accepted(panel, {
    action = "unlock",
    ownership_changed = true,
    product_id = skin.product_id,
    slot_view_dirty = true,
    notification = tostring(skin.name) .. " 已解锁",
  })
end

local function _unequip(root_state, role_id)
  local panel, rejected = transaction_result.panel_or_rejection(root_state)
  if rejected ~= nil then
    return rejected
  end
  role_id = role_id or panel.role_id
  transaction_state.apply_unequip(panel, role_id)
  return transaction_state.accepted(panel, {
    action = "unequip",
    unequipped = true,
    slot_view_dirty = true,
    host_action_attempted = transaction_context.has_unequip_adapter(),
    notification = "已脱下皮肤",
  })
end

local function _unlock_handler(fallback_source)
  return function(root_state, role_id, request)
    return _unlock_slot(root_state, role_id, request_shape.slot_index(request), request_shape.unlock_source(request, fallback_source))
  end
end

local function _equip_handler(root_state, role_id, request)
  return _equip_slot(root_state, role_id, request_shape.slot_index(request))
end

local function _activate_slot(root_state, role_id, request)
  local panel, rejected = transaction_result.panel_or_rejection(root_state)
  if rejected ~= nil then
    return rejected
  end
  role_id = role_id or panel.role_id
  local slot_index = request_shape.slot_index(request)
  local view = transaction_state.slot_view_model(panel, role_id, slot_index)
  if view.status == "equipped" then
    return _unequip(root_state, role_id)
  end
  return _equip_slot(root_state, role_id, slot_index)
end

local function _unknown_transaction(root_state)
  local panel = transaction_state.ensure_panel(root_state)
  return transaction_state.rejected(panel, "unknown_skin_transaction")
end

local REQUEST_HANDLERS = {
  open = function(root_state, role_id)
    return _open(root_state, role_id)
  end,
  close = function(root_state, role_id)
    return _close(root_state, role_id)
  end,
  page_next = function(root_state)
    return _page_delta(root_state, 1)
  end,
  next = function(root_state)
    return _page_delta(root_state, 1)
  end,
  page_prev = function(root_state)
    return _page_delta(root_state, -1)
  end,
  prev = function(root_state)
    return _page_delta(root_state, -1)
  end,
  unlock_slot = _unlock_handler("unlock_slot"),
  buy = _unlock_handler("buy"),
  gift = _unlock_handler("gift"),
  equip_slot = _equip_handler,
  equip = _equip_handler,
  activate_slot = _activate_slot,
  activate = _activate_slot,
  unequip = function(root_state, role_id)
    return _unequip(root_state, role_id)
  end,
}

function actions.handle_skin_transaction(root_state, role_id, request)
  local handler = REQUEST_HANDLERS[request_shape.kind(request)]
  if handler == nil then
    return _unknown_transaction(root_state)
  end
  return handler(root_state, role_id, request)
end

function actions.complete_skin_purchase(root_state, role_id, product_id)
  return completion.complete_skin_purchase(root_state, role_id, product_id)
end

-- Read-only slot/equip queries live in transaction_queries; re-exported here so
-- the transaction_actions API stays unchanged for the transaction facade.
actions.is_slot_equipped = queries.is_slot_equipped
actions.slot_view_model = queries.slot_view_model
actions.slot_view_models = queries.slot_view_models
actions.equipped_product = queries.equipped_product

return actions

