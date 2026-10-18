local number_utils = require("src.foundation.number")
local state = require("src.config.runtime_assets.state")
local results = require("src.config.runtime_assets.results")

local M = {}

function M.image_for_item(item_id, opts)
  return results.image_result("item.icon", item_id, "missing_item_icon", opts)
end

function M.image_for_chance_card(card_id, opts)
  return results.image_result("chance.icon", card_id, "missing_chance_card_icon", opts)
end

function M.image_for_skin_card(product_id, opts)
  return results.image_result("skin.card_image", product_id, "missing_skin_card_image", opts)
end

function M.empty_image(opts)
  return results.image_result("empty.image", "Empty", "missing_empty_image", opts)
end

function M.image_for_popup_card(kind, image_ref, opts)
  local meaning = kind == "item_card" and "popup.item_card_image" or "popup.chance_card_image"
  return results.image_result(meaning, image_ref, "missing_popup_card_image", opts)
end

function M.image_for_market_item(product_id, display_name, opts)
  local primary = results.image_result("market.item_icon", product_id, "missing_market_item_icon", opts)
  if primary.ok == true or display_name == nil or display_name == "" then
    return primary
  end
  local fallback = results.image_result("market.item_icon", display_name, "missing_market_item_icon", opts)
  fallback.primary_lookup_key = primary.lookup_key
  fallback.fallback_used = fallback.ok == true
  return fallback
end

function M.startup_item_slot_icon(slot_index, opts)
  local slot = number_utils.to_integer(slot_index)
  local raw_key = slot and state.startup_item_ids()[slot] or nil
  return results.image_result("ui.startup_item_slot_icon", raw_key, "missing_startup_item_icon", opts)
end

function M.skin_model_for_product(product_id, opts)
  local refs = state.refs(opts)
  local lookup_key = results.key(product_id)
  local asset_id = product_id ~= nil and (refs.skins or {})[lookup_key] or nil
  if asset_id == nil then
    return results.missing("skin.model", "missing_skin_model", {
      lookup_key = lookup_key,
    })
  end
  return results.result("skin.model", {
    asset_id = asset_id,
    lookup_key = lookup_key,
    fallback_used = false,
  })
end

function M.default_skin_model(opts)
  local asset_id = state.refs(opts).default_creature
  if asset_id == nil then
    return results.missing("skin.default_model", "missing_default_skin_model")
  end
  return results.result("skin.default_model", {
    asset_id = asset_id,
    fallback_used = false,
  })
end

return M

