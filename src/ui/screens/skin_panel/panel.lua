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

--[[ mutate4lua-manifest
version=4
projectHash=748f5c9d6e1eac12
scope.0.id=chunk:src/ui/screens/skin_panel/panel.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=196
scope.0.semanticHash=5c2a8e679a98c4a7
scope.1.id=function:_notify
scope.1.kind=function
scope.1.startLine=18
scope.1.endLine=26
scope.1.semanticHash=2c686d5c7739258f
scope.2.id=function:panel.sync_catalog
scope.2.kind=function
scope.2.startLine=31
scope.2.endLine=34
scope.2.semanticHash=d537922e05aae7ed
scope.3.id=function:_refresh_slots_for_owner
scope.3.kind=function
scope.3.startLine=36
scope.3.endLine=40
scope.3.semanticHash=0925e94ffae58435
scope.4.id=function:<anonymous>
scope.4.kind=function
scope.4.startLine=37
scope.4.endLine=39
scope.4.semanticHash=5647239230809532
scope.5.id=function:_panel_from_result
scope.5.kind=function
scope.5.startLine=42
scope.5.endLine=47
scope.5.semanticHash=bd88ac59b80bd2f7
scope.6.id=function:_result_key
scope.6.kind=function
scope.6.startLine=49
scope.6.endLine=54
scope.6.semanticHash=5968e7b255b60f57
scope.7.id=function:_notify_result
scope.7.kind=function
scope.7.startLine=56
scope.7.endLine=64
scope.7.semanticHash=7cc2864652a84143
scope.8.id=function:_switch_open_result
scope.8.kind=function
scope.8.startLine=66
scope.8.endLine=70
scope.8.semanticHash=b407b13008a86222
scope.9.id=function:_refresh_result_slots
scope.9.kind=function
scope.9.startLine=72
scope.9.endLine=76
scope.9.semanticHash=bd984f8c1f8a0bad
scope.10.id=function:_switch_close_result
scope.10.kind=function
scope.10.startLine=78
scope.10.endLine=82
scope.10.semanticHash=ee26f7b339cd6c0d
scope.11.id=function:_apply_transaction_result
scope.11.kind=function
scope.11.startLine=84
scope.11.endLine=92
scope.11.semanticHash=4f20d65aa54b6ad7
scope.12.id=function:_default_apply_transaction_result
scope.12.kind=function
scope.12.startLine=94
scope.12.endLine=96
scope.12.semanticHash=afa9b41072ba7956
scope.13.id=function:panel.apply_transaction_result
scope.13.kind=function
scope.13.startLine=98
scope.13.endLine=100
scope.13.semanticHash=1b5d975bd7739fc4
scope.14.id=function:_handle_transaction
scope.14.kind=function
scope.14.startLine=102
scope.14.endLine=105
scope.14.semanticHash=53b235add700d923
scope.15.id=function:panel.is_slot_equipped
scope.15.kind=function
scope.15.startLine=107
scope.15.endLine=109
scope.15.semanticHash=aba9250a8c6b104f
scope.16.id=function:panel.configure_equip
scope.16.kind=function
scope.16.startLine=111
scope.16.endLine=113
scope.16.semanticHash=c772a22f8680e278
scope.17.id=function:panel.configure_unequip
scope.17.kind=function
scope.17.startLine=115
scope.17.endLine=117
scope.17.semanticHash=c772a22f8680e278
scope.18.id=function:panel.configure_archive
scope.18.kind=function
scope.18.startLine=119
scope.18.endLine=121
scope.18.semanticHash=c772a22f8680e278
scope.19.id=function:panel.configure_catalog_for_tests
scope.19.kind=function
scope.19.startLine=123
scope.19.endLine=126
scope.19.semanticHash=e9e6dbe583e29db4
scope.20.id=function:panel.reset_for_tests
scope.20.kind=function
scope.20.startLine=128
scope.20.endLine=132
scope.20.semanticHash=b717a228b3c244fb
scope.21.id=function:panel.install_default_result_applier
scope.21.kind=function
scope.21.startLine=134
scope.21.endLine=136
scope.21.semanticHash=600a75ce96a391b3
scope.22.id=function:panel.open
scope.22.kind=function
scope.22.startLine=138
scope.22.endLine=141
scope.22.semanticHash=966fd1d6ab48649b
scope.23.id=function:panel.close
scope.23.kind=function
scope.23.startLine=143
scope.23.endLine=145
scope.23.semanticHash=ee4ee265f27468af
scope.24.id=function:panel.unlock
scope.24.kind=function
scope.24.startLine=147
scope.24.endLine=153
scope.24.semanticHash=e29eb3729ed8486f
scope.25.id=function:panel.equip
scope.25.kind=function
scope.25.startLine=155
scope.25.endLine=160
scope.25.semanticHash=c0d52f12aa4192ca
scope.26.id=function:_unequip
scope.26.kind=function
scope.26.startLine=162
scope.26.endLine=164
scope.26.semanticHash=39a74ad45798241f
scope.27.id=function:_page
scope.27.kind=function
scope.27.startLine=166
scope.27.endLine=168
scope.27.semanticHash=7c743a031ec72102
scope.28.id=function:<anonymous>#2
scope.28.kind=function
scope.28.startLine=171
scope.28.endLine=171
scope.28.semanticHash=3c26bf1ea8e4b724
scope.29.id=function:<anonymous>#3
scope.29.kind=function
scope.29.startLine=172
scope.29.endLine=172
scope.29.semanticHash=0f2488aaf77f0c6b
scope.30.id=function:<anonymous>#4
scope.30.kind=function
scope.30.startLine=173
scope.30.endLine=173
scope.30.semanticHash=0f2488aaf77f0c6b
scope.31.id=function:<anonymous>#5
scope.31.kind=function
scope.31.startLine=174
scope.31.endLine=174
scope.31.semanticHash=6ff409bbc3be92f3
scope.32.id=function:<anonymous>#6
scope.32.kind=function
scope.32.startLine=175
scope.32.endLine=180
scope.32.semanticHash=bb327769a6d7d268
scope.33.id=function:<anonymous>#7
scope.33.kind=function
scope.33.startLine=181
scope.33.endLine=181
scope.33.semanticHash=3c26bf1ea8e4b724
scope.34.id=function:<anonymous>#8
scope.34.kind=function
scope.34.startLine=182
scope.34.endLine=182
scope.34.semanticHash=b44059d4cf1a8a2f
scope.35.id=function:<anonymous>#9
scope.35.kind=function
scope.35.startLine=183
scope.35.endLine=183
scope.35.semanticHash=b44059d4cf1a8a2f
scope.36.id=function:panel.handle_action
scope.36.kind=function
scope.36.startLine=186
scope.36.endLine=193
scope.36.semanticHash=a6dd694c9e2284b5
]]
