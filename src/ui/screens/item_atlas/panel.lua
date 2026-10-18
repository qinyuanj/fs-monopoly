-- item_atlas 面板面(自 screens/item_atlas.lua 拆分,>100 mutation sites 行为保持):
-- 开屏/翻页/图集选择/放大隐藏/点击派发。
-- #543:图鉴放大卡回归纯浏览用途,不再承担获得展示,dismiss 只收浏览放大卡,
-- 不向回合机派发 action_anim_done(获得展示的提前关闭归卡牌展示屏弹窗)。
local number_utils = require("src.foundation.number")
local canvas = require("src.ui.coord.canvas_coordinator")
local base_nodes = require("src.ui.schema.base")
local item_atlas_nodes = require("src.ui.schema.item_atlas")
local item_atlas_view = require("src.ui.render.widgets.item_atlas")
local panel_helpers = require("src.ui.render.support.panel_helpers")
local panel_tip = require("src.ui.coord.panel_tip")
local atlas_state = require("src.ui.screens.item_atlas.item_atlas_state")

local panel = {}

local function _notify(text, key)
  panel_tip.enqueue("ui.item_atlas", text, key)
end

local function _refresh_page_for_owner(state, atlas)
  return panel_helpers.with_owner_role(state, atlas.role_id, function()
    return item_atlas_view.refresh_page(state, atlas_state.catalog(), atlas.page_index)
  end)
end

local function _hide_enlarged_for_owner(state, atlas)
  return panel_helpers.with_owner_role(state, atlas.role_id, function()
    return item_atlas_view.hide_enlarged(state)
  end)
end

-- 选中态 + 放大覆盖层显隐的原子清理(#583):open/close/翻页/点空白/取消选中
-- 全部经此收口——close 曾漏掉这对调用,导致陈旧放大卡随图鉴 canvas 复活。
local function _clear_enlarged(state, atlas)
  atlas.selected_item_id = nil
  return _hide_enlarged_for_owner(state, atlas)
end

local function _show_enlarged_for_owner(state, atlas, item_id)
  return panel_helpers.with_owner_role(state, atlas.role_id, function()
    return item_atlas_view.show_enlarged(state, item_id)
  end)
end

function panel.open(state, role_id)
  local atlas = atlas_state.ensure(state)
  atlas.open = true
  atlas.role_id = role_id
  atlas.page_index = atlas_state.clamp_page(atlas.page_index)
  canvas.switch_by_role_id(state and state.ui, item_atlas_nodes.canvas, role_id)
  _refresh_page_for_owner(state, atlas)
  _clear_enlarged(state, atlas)
  _notify("图鉴已打开", "item_atlas:open:" .. tostring(role_id))
  return atlas
end

-- #583:close 与 open/翻页/点空白同口径经 _clear_enlarged 清理放大覆盖层
-- (选中态 + 三节点 per-role 显隐)——覆盖层住图鉴 canvas,关屏不清会让陈旧
-- 放大卡随图鉴 canvas 的下次显示复活/滞留。覆盖层显隐按图鉴 owner
-- (atlas.role_id)落,与关屏 canvas 切换的显式 role_id 互不干扰。
function panel.close(state, role_id)
  local atlas = atlas_state.ensure(state)
  atlas.open = false
  _clear_enlarged(state, atlas)
  canvas.switch_by_role_id(state and state.ui, base_nodes.canvas, role_id or atlas.role_id)
  _notify("已关闭", "item_atlas:close")
  return atlas
end

local function _move_page(state, role_id, delta)
  local atlas = atlas_state.ensure(state)
  atlas.role_id = role_id or atlas.role_id
  atlas.page_index = atlas_state.clamp_page(atlas.page_index + delta)
  _refresh_page_for_owner(state, atlas)
  _clear_enlarged(state, atlas)
  return atlas
end

local function _page_next(state, role_id)
  return _move_page(state, role_id, 1)
end

local function _page_prev(state, role_id)
  return _move_page(state, role_id, -1)
end

local function _dismiss(state, role_id)
  local atlas = atlas_state.ensure(state)
  atlas.role_id = role_id or atlas.role_id
  _clear_enlarged(state, atlas)
  return atlas
end

local function _select_slot(state, slot_index, role_id)
  local atlas = atlas_state.ensure(state)
  atlas.role_id = role_id or atlas.role_id
  local item = atlas_state.item_at(atlas, slot_index)
  if item and atlas.selected_item_id == item.id then
    _clear_enlarged(state, atlas)
  elseif item then
    atlas.selected_item_id = item.id
    _show_enlarged_for_owner(state, atlas, item.id)
  end
  return atlas
end

local _STRING_ACTION_HANDLERS = {
  close   = function(state, role_id, _)    return panel.close(state, role_id) end,
  next    = function(state, role_id, _)    return _page_next(state, role_id) end,
  prev    = function(state, role_id, _)    return _page_prev(state, role_id) end,
  dismiss = function(state, role_id, _)    return _dismiss(state, role_id) end,
}

local function _ensure_atlas_for_role(state, role_id)
  local atlas = atlas_state.ensure(state)
  atlas.role_id = role_id or atlas.role_id
  return atlas
end

function panel.handle_action(state, action, role_id)
  local handler = _STRING_ACTION_HANDLERS[action]
  if handler then return handler(state, role_id, action) end
  -- select 分支必须无条件调 _select_slot（slot_index 允许为 nil）。
  if type(action) == "table" and action.type == "select" then
    return _select_slot(state, action.slot_index, role_id)
  end
  local slot_index = number_utils.to_integer(action)
  if slot_index ~= nil then return _select_slot(state, slot_index, role_id) end
  return _ensure_atlas_for_role(state, role_id)
end

return panel

