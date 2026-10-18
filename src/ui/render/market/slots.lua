local market_layout = require("src.ui.schema.market_layout")
local ui_controls = require("src.ui.render.support.ui_controls")
local items_cfg = require("src.config.content.items")
local market_catalog = require("src.config.content.market_catalog")
local slot_assets = require("src.ui.render.market.slot_assets")

local market_view_slots = {}

local _items_cfg_by_id = {}
for _, cfg in ipairs(items_cfg) do
  _items_cfg_by_id[cfg.id] = cfg
end

local function _item_cfg_by_id(product_id)
  return _items_cfg_by_id[product_id]
end

local _market_entry_by_id = market_catalog.entry_by_id

local function _resolve_market_entry(product_id)
  local entry = _market_entry_by_id(product_id)
  local cfg = _item_cfg_by_id(product_id)
  return entry, cfg
end

local function _name_of(entry, key)
  return entry and entry[key] or nil
end

-- 名称按 entry → cfg → opt 顺序回落,全缺省时回落 product_id 字面量。
local function _resolve_market_name(opt, product_id, entry, cfg)
  local name = _name_of(entry, "name") or _name_of(cfg, "name") or _name_of(opt, "label")
  if name ~= nil then
    return name
  end
  return tostring(product_id)
end

local function _set_market_slot_hidden(ui, slot)
  ui_controls.set_slot_state(ui, slot, {
    button = { visible = false, touch_enabled = false },
    label = { visible = false, touch_enabled = false },
    frame = { visible = false, touch_enabled = false },
    sold_out_badge = { visible = false, touch_enabled = false },
    sold_out_label = { visible = false, touch_enabled = false },
  })
end

local function _for_each_market_slot(callback)
  local buttons = market_layout.item_buttons
  local labels = market_layout.item_labels
  local frames = market_layout.item_frames
  for index = 1, math.max(#buttons, #labels, #frames) do
    local button = buttons[index]
    local label = labels[index]
    local frame = frames[index]
    if button and label and frame then
      callback(index, {
        button = button,
        label = label,
        frame = frame,
        sold_out_badge = market_layout.sold_out_badges[index],
        sold_out_label = market_layout.sold_out_labels[index],
      })
    end
  end
end

local function _set_market_slot_visible(ui, slot, opt)
  -- 底框纹理由 EUI 烘焙默认/Empty 直接承担,不再按稀有度写纹理(#511)。
  local opt_id = opt.id or opt
  local entry, cfg = _resolve_market_entry(opt_id)
  local name = _resolve_market_name(opt, opt_id, entry, cfg)
  ui:set_label(slot.label, name)
  ui_controls.set_slot_state(ui, slot, {
    label = { visible = true, touch_enabled = false },
    button = { visible = true, touch_enabled = true },
    frame = { visible = true, touch_enabled = false },
    sold_out_badge = { visible = opt.sold_out == true, touch_enabled = false },
    sold_out_label = { visible = opt.sold_out == true, touch_enabled = false },
  })
  return opt_id
end

local function _set_market_slot(ui, slot, opt)
  if not opt then
    _set_market_slot_hidden(ui, slot)
    return nil
  end
  return _set_market_slot_visible(ui, slot, opt)
end

local function _has_option_id(option_ids, option_id)
  for _, value in pairs(option_ids or {}) do
    if value == option_id then
      return true
    end
  end
  return false
end

local function _opt_id(opt)
  return opt and (opt.id or opt) or nil
end

local function _entry_for_opt(opt)
  local opt_id = _opt_id(opt)
  return opt_id and _market_entry_by_id(opt_id) or nil
end

-- 未登记商品(entry 缺省)或显式未禁用时保留该选项。
local function _should_show_option(entry)
  return entry == nil or entry.market_enabled ~= false
end

function market_view_slots.filter_market_options(options)
  local visible_options = {}
  for _, opt in ipairs(options or {}) do
    if _should_show_option(_entry_for_opt(opt)) then
      visible_options[#visible_options + 1] = opt
    end
  end
  return visible_options
end

function market_view_slots.hide_market_slots(ui)
  _for_each_market_slot(function(_, slot)
    _set_market_slot_hidden(ui, slot)
  end)
end

function market_view_slots.populate_market_slots(ui, options)
  local option_ids = {}
  local first_buyable = nil
  _for_each_market_slot(function(index, slot)
    local opt = options[index]
    if opt and opt.can_buy == true and first_buyable == nil then
      first_buyable = opt.id or opt
    end
    local opt_id = _set_market_slot(ui, slot, opt)
    option_ids[index] = opt_id
  end)
  return {
    option_ids = option_ids,
    first_buyable = first_buyable,
  }
end

function market_view_slots.resolve_selected_option(option_ids, selected_option_id, first_buyable)
  local selected = selected_option_id
  if not _has_option_id(option_ids, selected) then
    selected = nil
  end
  if selected == nil then
    return first_buyable or option_ids[1]
  end
  return selected
end

function market_view_slots.resolve_selection(option_id, image_refs)
  assert(option_id ~= nil, "missing market option_id")
  local entry, cfg = _resolve_market_entry(option_id)
  assert(entry ~= nil, "missing market entry")
  return {
    entry = entry,
    cfg = cfg,
    price_text = slot_assets.price_text(entry),
    icon_key = slot_assets.selection_icon_key(image_refs, option_id, entry, cfg),
  }
end

return market_view_slots

