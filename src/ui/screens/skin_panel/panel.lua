-- skin_panel 面板门面(#204):把面板动作映射为皮肤归属 seam 的命令与查询,再把
-- 领域结果映射为展示——canvas 切换、槽位刷新与提示。归属规则不在这里。
local skin_ownership = require("src.ui.seams.skin_ownership")
local tip_queue = require("src.foundation.tips")
local canvas = require("src.ui.coord.canvas_coordinator")
local base_nodes = require("src.ui.schema.base")
local skin_nodes = require("src.ui.schema.skin")
local skin_panel_view = require("src.ui.render.widgets.skin_panel")
local slot_views = require("src.ui.render.widgets.skin_panel_slot_views")
local panel_helpers = require("src.ui.render.support.panel_helpers")
local panel_state = require("src.ui.screens.skin_panel.skin_panel_state")
local request_shape = require("src.ui.schema.skin_request")
local number_utils = require("src.foundation.number")

local panel = {}

local UNLOCK_REFUSED_TIP = "皮肤尚未解锁"

-- 购买被拒的提示:存档不可用单独说明;角色缺失与已有在途购买不提示;其余
-- (非可购买皮肤、买家解析失败、付费网关拒绝)一律按尚未解锁提示。
local SILENT_PURCHASE_REFUSALS = {
  missing_state = true,
  missing_role = true,
  purchase_in_flight = true,
}

local PURCHASE_REFUSAL_TIPS = {
  archive_unavailable = "存档未开启，暂时无法购买皮肤",
}

-- 提示去重键:skin_panel:<动作>:<角色>:<商品>。
local function _tip(action, role_id, product_id, text, opts)
  if opts and opts.silent == true then
    return
  end
  tip_queue.enqueue({
    text = text,
    duration = 2.0,
    dedupe_key = "skin_panel:" .. action .. ":" .. tostring(role_id) .. ":" .. tostring(product_id or ""),
    blocks_inter_turn = false,
    source = "ui.skin_panel",
  })
end

local function _refresh_slots(state, p)
  return panel_helpers.with_owner_role(state, p.role_id, function()
    return skin_panel_view.refresh_slots(state, skin_ownership.catalog())
  end)
end

local function _switch_to_base(state, role_id)
  canvas.switch_by_role_id(state and state.ui, base_nodes.canvas, role_id)
end

local function _skin_at(p, slot_index)
  return slot_views.skin_at(p, slot_index, skin_ownership.catalog())
end

-- 换装成功(直接穿上或购买完成)的展示:收屏、刷新槽位、回基础屏、提示。
local function _show_equipped(state, p, role_id, action, skin)
  p.open = false
  _refresh_slots(state, p)
  _switch_to_base(state, role_id)
  _tip(action, role_id, skin.product_id, "已换装 " .. tostring(skin.name))
end

local function _on_purchase_complete(state, result)
  if result.accepted ~= true then
    return
  end
  local p = panel_state.ensure(state)
  local skin = slot_views.skin_by_product(skin_ownership.catalog(), result.product_id)
  if skin == nil then
    return
  end
  _show_equipped(state, p, p.role_id, "purchase_complete", skin)
end

local function _start_purchase(state, p, role_id, skin)
  local result = skin_ownership.start_purchase(state, role_id, skin.product_id, function(completed)
    _on_purchase_complete(state, completed)
  end)
  if result.accepted ~= true and not SILENT_PURCHASE_REFUSALS[result.reason] then
    _tip("unknown", role_id, nil, PURCHASE_REFUSAL_TIPS[result.reason] or UNLOCK_REFUSED_TIP)
  end
  return p
end

function panel.open(state, role_id)
  local p = panel_state.ensure(state)
  p.open = true
  p.role_id = role_id
  p.page_index = 1
  local restored = skin_ownership.sync_on_shop_open(state, role_id)
  canvas.switch_by_role_id(state.ui, skin_nodes.canvas, role_id)
  _refresh_slots(state, p)
  _tip("open", role_id, restored, "皮肤已打开")
  return p
end

function panel.close(state, role_id, opts)
  local p = panel_state.ensure(state)
  p.open = false
  local effective_role = role_id or p.role_id
  _switch_to_base(state, effective_role)
  _tip("close", effective_role, nil, "已关闭", opts)
  return p
end

local function _page(state, delta)
  local p = panel_state.ensure(state)
  p.page_index = slot_views.clamp_page((p.page_index or 1) + delta, skin_ownership.catalog())
  _refresh_slots(state, p)
  return p
end

-- 礼物等非购买来源的解锁(source 仅标记来源,归属不分来源)。
function panel.unlock(state, role_id, _source, slot_index)
  local p = panel_state.ensure(state)
  local effective_role = role_id or p.role_id
  local skin = _skin_at(p, slot_index)
  if skin == nil then
    return p
  end
  if skin_ownership.grant(state, effective_role, skin.product_id).accepted == true then
    _refresh_slots(state, p)
    _tip("unlock", effective_role, skin.product_id, tostring(skin.name) .. " 已解锁")
  end
  return p
end

-- 已拥有则穿上,未拥有则发起购买。
function panel.equip(state, role_id, slot_index)
  local p = panel_state.ensure(state)
  local effective_role = role_id or p.role_id
  local skin = _skin_at(p, slot_index)
  if skin == nil then
    return p
  end
  if not skin_ownership.owns(state, effective_role, skin.product_id) then
    return _start_purchase(state, p, effective_role, skin)
  end
  if skin_ownership.equip(state, effective_role, skin.product_id).accepted == true then
    _show_equipped(state, p, effective_role, "equip", skin)
  end
  return p
end

local function _unequip(state, role_id)
  local p = panel_state.ensure(state)
  local effective_role = role_id or p.role_id
  if skin_ownership.unequip(state, effective_role).accepted == true then
    _refresh_slots(state, p)
    _tip("unequip", effective_role, nil, "已脱下皮肤")
  end
  return p
end

-- 槽位按钮:已穿戴则脱下,否则穿上(或发起购买)。
local function _activate_slot(state, role_id, slot_index)
  local p = panel_state.ensure(state)
  local effective_role = role_id or p.role_id
  local skin = _skin_at(p, slot_index)
  if slot_views.status(state, effective_role, skin) == "equipped" then
    return _unequip(state, effective_role)
  end
  return panel.equip(state, effective_role, slot_index)
end

local _ACTION_HANDLERS = {
  close   = function(state, role_id, _)  return panel.close(state, role_id) end,
  buy     = function(state, role_id, a)  return panel.unlock(state, role_id, "buy", request_shape.slot_index(a)) end,
  gift    = function(state, role_id, a)  return panel.unlock(state, role_id, "gift", request_shape.slot_index(a)) end,
  equip   = function(state, role_id, a)  return panel.equip(state, role_id, request_shape.slot_index(a)) end,
  activate_slot = function(state, role_id, a) return _activate_slot(state, role_id, request_shape.slot_index(a)) end,
  unequip = function(state, role_id, _)  return _unequip(state, role_id) end,
  next    = function(state, _, _)        return _page(state, 1) end,
  prev    = function(state, _, _)        return _page(state, -1) end,
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
