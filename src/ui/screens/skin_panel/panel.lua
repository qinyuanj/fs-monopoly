-- skin_panel 面板门面(自 screens/skin_panel.lua 拆分,>100 mutation sites
-- 行为保持):事务派发、结果应用(canvas 切换/槽位刷新/提示)、公开动作 API。
local cosmetics_ports = require("src.ui.seams.cosmetics")
local transaction = cosmetics_ports.build().transaction
local tip_queue = require("src.foundation.tips")
local canvas = require("src.ui.coord.canvas_coordinator")
local base_nodes = require("src.ui.schema.base")
local skin_nodes = require("src.ui.schema.skin")
local skin_panel_view = require("src.ui.render.widgets.skin_panel")
local panel_helpers = require("src.ui.render.support.panel_helpers")
local panel_state = require("src.ui.screens.skin_panel.skin_panel_state")
local request_shape = require("src.ui.schema.skin_request")
local number_utils = require("src.foundation.number")

local panel = {}

local function _notify(text, key)
  tip_queue.enqueue({
    text = text,
    duration = 2.0,
    dedupe_key = key,
    blocks_inter_turn = false,
    source = "ui.skin_panel",
  })
end

-- configure/reset/open 时从 transaction_context 拉新排序目录，供槽位渲染使用。
function panel.sync_catalog()
  transaction.refresh_catalog()
  panel.catalog = transaction.catalog
end

local function _refresh_slots_for_owner(state, p)
  return panel_helpers.with_owner_role(state, p.role_id, function()
    return skin_panel_view.refresh_slots(state, panel.catalog)
  end)
end

local function _panel_from_result(state, result)
  if result and result.panel then
    return result.panel
  end
  return panel_state.ensure(state)
end

local function _result_key(result, role_id)
  local product_id = result.product_id or result.equipped_product or ""
  return "skin_panel:" .. tostring(result.action or "unknown")
    .. ":" .. tostring(role_id)
    .. ":" .. tostring(product_id)
end

local function _notify_result(result, role_id, opts)
  if opts and opts.silent == true then
    return
  end
  if result == nil or result.notification == nil then
    return
  end
  _notify(result.notification, _result_key(result, role_id))
end

local function _switch_open_result(state, effective_role, result)
  if result and result.action == "open" then
    canvas.switch_by_role_id(state and state.ui, skin_nodes.canvas, effective_role)
  end
end

local function _refresh_result_slots(state, p, result)
  if result and result.slot_view_dirty == true then
    _refresh_slots_for_owner(state, p)
  end
end

local function _switch_close_result(state, effective_role, result)
  if result and result.panel_should_close == true then
    canvas.switch_by_role_id(state and state.ui, base_nodes.canvas, result.role_id or effective_role)
  end
end

local function _apply_transaction_result(state, role_id, result, opts)
  local p = _panel_from_result(state, result)
  local effective_role = role_id or p.role_id
  _switch_open_result(state, effective_role, result)
  _refresh_result_slots(state, p, result)
  _switch_close_result(state, effective_role, result)
  _notify_result(result, effective_role, opts)
  return p
end

local function _default_apply_transaction_result(state, result)
  return _apply_transaction_result(state, nil, result, {})
end

function panel.apply_transaction_result(state, result, opts)
  return _apply_transaction_result(state, nil, result, opts or {})
end

local function _handle_transaction(state, role_id, request, opts)
  local result = transaction.handle_skin_transaction(state, role_id, request)
  return _apply_transaction_result(state, role_id, result, opts)
end

function panel.is_slot_equipped(state, slot_index)
  return transaction.is_slot_equipped(state, slot_index)
end

function panel.configure_equip(callback)
  transaction.configure_equip(callback)
end

function panel.configure_unequip(callback)
  transaction.configure_unequip(callback)
end

function panel.configure_archive(archive)
  transaction.configure_archive(archive)
end

function panel.configure_catalog_for_tests(catalog)
  transaction.configure_catalog_for_tests(catalog)
  panel.sync_catalog()
end

function panel.reset_for_tests()
  transaction.reset_for_tests()
  panel.sync_catalog()
  transaction.configure_transaction_result_applier(_default_apply_transaction_result)
end

function panel.install_default_result_applier()
  transaction.configure_transaction_result_applier(_default_apply_transaction_result)
end

function panel.open(state, role_id)
  panel.sync_catalog()  -- open 前重新排序，确保槽位渲染使用当前目录
  return _handle_transaction(state, role_id, { type = "open" })
end

function panel.close(state, role_id, opts)
  return _handle_transaction(state, role_id, { type = "close" }, opts)
end

function panel.unlock(state, role_id, source, slot_index)
  return _handle_transaction(state, role_id, {
    type = "unlock_slot",
    source = source,
    slot_index = slot_index,
  })
end

function panel.equip(state, role_id, slot_index)
  return _handle_transaction(state, role_id, {
    type = "equip_slot",
    slot_index = slot_index,
  })
end

local function _unequip(state, role_id)
  return _handle_transaction(state, role_id, { type = "unequip" })
end

local function _page(state, request_type)
  return _handle_transaction(state, nil, { type = request_type }, { silent = true })
end

local _ACTION_HANDLERS = {
  close   = function(state, role_id, _)  return panel.close(state, role_id) end,
  buy     = function(state, role_id, a)  return panel.unlock(state, role_id, "buy", request_shape.slot_index(a)) end,
  gift    = function(state, role_id, a)  return panel.unlock(state, role_id, "gift", request_shape.slot_index(a)) end,
  equip   = function(state, role_id, a)  return panel.equip(state, role_id, request_shape.slot_index(a)) end,
  activate_slot = function(state, role_id, a)
    return _handle_transaction(state, role_id, {
      type = "activate_slot",
      slot_index = request_shape.slot_index(a),
    })
  end,
  unequip = function(state, role_id, _)  return _unequip(state, role_id) end,
  next    = function(state, _, _)        return _page(state, "page_next") end,
  prev    = function(state, _, _)        return _page(state, "page_prev") end,
}

function panel.handle_action(state, action, role_id)
  local action_type = request_shape.kind(action)
  local handler = _ACTION_HANDLERS[action_type]
  if handler then return handler(state, role_id, action) end
  local slot_index = number_utils.to_integer(action)
  if slot_index ~= nil then return panel.equip(state, role_id, slot_index) end
  return panel_state.ensure(state)
end

return panel

