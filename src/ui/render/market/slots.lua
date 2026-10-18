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

--[[ mutate4lua-manifest
version=4
projectHash=2ee31b7d302e4494
scope.0.id=chunk:src/ui/render/market/slots.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=176
scope.0.semanticHash=da0550cc244d565f
scope.1.id=function:_item_cfg_by_id
scope.1.kind=function
scope.1.startLine=14
scope.1.endLine=16
scope.1.semanticHash=fc8eda1d7903d2b1
scope.2.id=function:_resolve_market_entry
scope.2.kind=function
scope.2.startLine=20
scope.2.endLine=24
scope.2.semanticHash=b1c2d5ab5f92b050
scope.3.id=function:_name_of
scope.3.kind=function
scope.3.startLine=26
scope.3.endLine=28
scope.3.semanticHash=cd6b189045fad21d
scope.4.id=function:_resolve_market_name
scope.4.kind=function
scope.4.startLine=31
scope.4.endLine=37
scope.4.semanticHash=bcadd0845e4aadd0
scope.5.id=function:_set_market_slot_hidden
scope.5.kind=function
scope.5.startLine=39
scope.5.endLine=47
scope.5.semanticHash=09bc1f46584c3d09
scope.6.id=function:_for_each_market_slot
scope.6.kind=function
scope.6.startLine=49
scope.6.endLine=67
scope.6.semanticHash=cf4b16b9ec758ab9
scope.7.id=function:_set_market_slot_visible
scope.7.kind=function
scope.7.startLine=69
scope.7.endLine=83
scope.7.semanticHash=763b319124f52e63
scope.8.id=function:_set_market_slot
scope.8.kind=function
scope.8.startLine=85
scope.8.endLine=91
scope.8.semanticHash=e54bd7dcf3c88bba
scope.9.id=function:_has_option_id
scope.9.kind=function
scope.9.startLine=93
scope.9.endLine=100
scope.9.semanticHash=4ac320f0f671bc12
scope.10.id=function:_opt_id
scope.10.kind=function
scope.10.startLine=102
scope.10.endLine=104
scope.10.semanticHash=e911848e1476429f
scope.11.id=function:_entry_for_opt
scope.11.kind=function
scope.11.startLine=106
scope.11.endLine=109
scope.11.semanticHash=965e68066e605d8c
scope.12.id=function:_should_show_option
scope.12.kind=function
scope.12.startLine=112
scope.12.endLine=114
scope.12.semanticHash=094f3635d2503291
scope.13.id=function:market_view_slots.filter_market_options
scope.13.kind=function
scope.13.startLine=116
scope.13.endLine=124
scope.13.semanticHash=901fb69a4e28b300
scope.14.id=function:market_view_slots.hide_market_slots
scope.14.kind=function
scope.14.startLine=126
scope.14.endLine=130
scope.14.semanticHash=71a9b58e87575026
scope.15.id=function:<anonymous>
scope.15.kind=function
scope.15.startLine=127
scope.15.endLine=129
scope.15.semanticHash=4ad1b5cb81e9ede6
scope.16.id=function:market_view_slots.populate_market_slots
scope.16.kind=function
scope.16.startLine=132
scope.16.endLine=147
scope.16.semanticHash=d6b215d104696a38
scope.17.id=function:<anonymous>#2
scope.17.kind=function
scope.17.startLine=135
scope.17.endLine=142
scope.17.semanticHash=a0111a4087a6645a
scope.18.id=function:market_view_slots.resolve_selected_option
scope.18.kind=function
scope.18.startLine=149
scope.18.endLine=158
scope.18.semanticHash=d75a14722a19b3a9
scope.19.id=function:market_view_slots.resolve_selection
scope.19.kind=function
scope.19.startLine=160
scope.19.endLine=170
scope.19.semanticHash=56a14edd87aeb358
]]
