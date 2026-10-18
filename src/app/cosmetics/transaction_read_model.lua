local transaction_context = require("src.app.cosmetics.transaction_context")
local number_utils = require("src.foundation.number")

local read_model = {}

local PAGE_SIZE = 6

function read_model.role_key(role_id)
  if role_id == nil then
    return nil
  end
  return tostring(role_id)
end

function read_model.slot_index(panel, slot_index)
  local slot = number_utils.to_integer(slot_index) or 1
  return ((panel and panel.page_index or 1) - 1) * PAGE_SIZE + slot
end

function read_model.skin_at(panel, slot_index, catalog)
  local effective_catalog = catalog or transaction_context.catalog()
  return effective_catalog[read_model.slot_index(panel, slot_index)]
end

function read_model.skin_by_product(product_id)
  for _, skin in ipairs(transaction_context.catalog()) do
    if skin.product_id == product_id then
      return skin
    end
  end
  return nil
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

local function _owned_map_for_role(panel, key)
  return key and panel and panel.owned_by_role and panel.owned_by_role[key] or nil
end

local function _equipped_id_for_role(panel, key)
  return panel and panel.selected_by_role and panel.selected_by_role[key] or nil
end

local function _slot_status(panel, role_id, skin)
  if skin == nil then
    return "empty"
  end
  local key = read_model.role_key(role_id)
  local owned_map = _owned_map_for_role(panel, key)
  if owned_map == nil or owned_map[skin.product_id] ~= true then
    return "locked"
  end
  if _equipped_id_for_role(panel, key) == skin.product_id then
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

local function _price_icon_visible(skin, status)
  return _has_price(skin) and not _is_owned_status(status)
end

local function _skin_field(skin, key)
  return skin and skin[key] or nil
end

local function _skin_fields(skin)
  return {
    has_skin = skin ~= nil,
    product_id = _skin_field(skin, "product_id"),
    name = _skin_field(skin, "name"),
    unlock = _skin_field(skin, "unlock"),
  }
end

function read_model.slot_view_model(panel, role_id, slot_index, catalog)
  local skin = read_model.skin_at(panel, slot_index, catalog)
  local status = _slot_status(panel, role_id or (panel and panel.role_id), skin)
  local button_text, button_touch_enabled = _button_props(skin, status)
  local fields = _skin_fields(skin)
  return {
    slot_index = number_utils.to_integer(slot_index) or 1,
    catalog_index = read_model.slot_index(panel, slot_index),
    skin = skin,
    has_skin = fields.has_skin,
    product_id = fields.product_id,
    name = fields.name,
    unlock = fields.unlock,
    status = status,
    button_text = button_text,
    button_touch_enabled = button_touch_enabled,
    price_icon_visible = _price_icon_visible(skin, status),
  }
end

function read_model.slot_view_models(panel, role_id, catalog)
  local views = {}
  for slot_index = 1, PAGE_SIZE do
    views[slot_index] = read_model.slot_view_model(panel, role_id, slot_index, catalog)
  end
  return views
end

function read_model.clamp_page(page_index)
  return number_utils.clamp(page_index, 1, number_utils.page_count(#transaction_context.catalog(), PAGE_SIZE))
end

return read_model

