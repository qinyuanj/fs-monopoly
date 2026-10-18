local runtime_assets = require("src.config.runtime_assets")
local number_utils = require("src.foundation.number")

local slot_assets = {}

local function _asset_opts(refs)
  if type(refs) ~= "table" then
    return nil
  end
  if type(refs.refs) == "table" or type(refs.images) == "table" then
    return refs
  end
  return { refs = { images = refs } }
end

local function _item_display_name(cfg, entry)
  return (cfg and cfg.name) or (entry and entry.name)
end

local function _icon_key(refs, product_id, entry, cfg)
  local image = runtime_assets.image_for_market_item(product_id, _item_display_name(cfg, entry), _asset_opts(refs))
  return image.ok == true and image.image_key or nil
end

function slot_assets.price_text(entry)
  local currency = assert(
    entry.currency ~= nil and entry.currency ~= "" and entry.currency,
    "missing market currency"
  )
  return number_utils.format_integer_part(entry.price) .. " " .. tostring(currency)
end

local function _empty_icon_key(refs)
  return runtime_assets.empty_image(_asset_opts(refs)).image_key
end

function slot_assets.selection_icon_key(refs, option_id, entry, cfg)
  return _icon_key(refs, option_id, entry, cfg)
    or _empty_icon_key(refs)
end

return slot_assets

