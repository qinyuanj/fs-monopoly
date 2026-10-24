-- 皮肤商店槽位视图模型(#204,自 app 交易读模型迁入):按页码把目录切成 6 个槽位,
-- 槽位状态(空/未拥有/已拥有/已穿戴)经皮肤归属 seam 的纯查询得出,按钮文案、
-- 可点与价格图标在这里映射。面板态缺失时按第 1 页、无主角色处理。
local skin_ownership = require("src.ui.seams.skin_ownership")
local number_utils = require("src.foundation.number")

local slot_views = {}

local PAGE_SIZE = 6

function slot_views.catalog_index(panel, slot_index)
  local slot = number_utils.to_integer(slot_index) or 1
  return ((panel and panel.page_index or 1) - 1) * PAGE_SIZE + slot
end

function slot_views.skin_at(panel, slot_index, catalog)
  return catalog[slot_views.catalog_index(panel, slot_index)]
end

function slot_views.skin_by_product(catalog, product_id)
  for _, skin in ipairs(catalog) do
    if skin.product_id == product_id then
      return skin
    end
  end
  return nil
end

function slot_views.clamp_page(page_index, catalog)
  return number_utils.clamp(page_index, 1, number_utils.page_count(#catalog, PAGE_SIZE))
end

local function _button_text_for_locked(skin)
  if skin.unlock == "gift" and skin.gift_name then
    return skin.gift_name
  end
  if skin.price ~= nil then
    return tostring(skin.price)
  end
  return ""
end

local BUTTON_PROPS = {
  owned = { text = "穿上", touch_enabled = true },
  equipped = { text = "脱下", touch_enabled = true },
  empty = { text = "", touch_enabled = false },
}

function slot_views.status(state, role_id, skin)
  if skin == nil then
    return "empty"
  end
  if not skin_ownership.owns(state, role_id, skin.product_id) then
    return "locked"
  end
  if skin_ownership.equipped(state, role_id) == skin.product_id then
    return "equipped"
  end
  return "owned"
end

local function _button_props(skin, status)
  if status == "locked" and skin ~= nil then
    return _button_text_for_locked(skin), skin.unlock == "purchase"
  end
  local props = BUTTON_PROPS[status] or BUTTON_PROPS.empty
  return props.text, props.touch_enabled
end

local function _has_price(skin)
  return skin ~= nil and skin.unlock == "purchase" and skin.price ~= nil and skin.currency ~= nil
end

local function _is_owned_status(status)
  return status == "owned" or status == "equipped"
end

local function _skin_field(skin, key)
  return skin and skin[key] or nil
end

function slot_views.build(state, panel, slot_index, catalog)
  local skin = slot_views.skin_at(panel, slot_index, catalog)
  local status = slot_views.status(state, panel and panel.role_id, skin)
  local button_text, button_touch_enabled = _button_props(skin, status)
  return {
    slot_index = number_utils.to_integer(slot_index) or 1,
    catalog_index = slot_views.catalog_index(panel, slot_index),
    skin = skin,
    has_skin = skin ~= nil,
    product_id = _skin_field(skin, "product_id"),
    name = _skin_field(skin, "name"),
    unlock = _skin_field(skin, "unlock"),
    status = status,
    button_text = button_text,
    button_touch_enabled = button_touch_enabled,
    price_icon_visible = _has_price(skin) and not _is_owned_status(status),
  }
end

function slot_views.build_page(state, catalog)
  local panel = state and state.ui and state.ui.skin_panel or nil
  local views = {}
  for slot_index = 1, PAGE_SIZE do
    views[slot_index] = slot_views.build(state, panel, slot_index, catalog)
  end
  return views
end

return slot_views
