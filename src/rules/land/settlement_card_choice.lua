local inventory = require("src.rules.items.inventory")
local item_ids = require("src.config.gameplay.item_ids")
local land_actions = require("src.rules.land.actions")
local shared = require("src.rules.land.settlement_shared")

local card_choice = {}

local function _rent_card_executor(execute)
  return function(game, player_id, tile_id)
    execute(game, player_id, tile_id)
    return true
  end
end

local function _ignore_selected_rent_card()
  return false
end

local rent_card_executors = {
  strong = _rent_card_executor(land_actions.execute_strong_card),
  free = _rent_card_executor(land_actions.execute_free_card),
}

local function _execute_selected_rent_card(game, player_id, tile_id, card_kind)
  local executor = rent_card_executors[card_kind] or _ignore_selected_rent_card
  return executor(game, player_id, tile_id)
end

local function _try_auto_free_rent(game, player_id, tile_id, card_kind)
  if card_kind ~= "strong" then
    return nil
  end
  local player = shared.resolve_actor(game, player_id)
  if player == nil then
    return shared.reject("missing_actor")
  end
  if inventory.find_index(player, item_ids.free_rent) then
    land_actions.execute_free_card(game, player_id, tile_id)
    return { ok = true, status = "resolved", effect_id = "free_rent" }
  end
  return nil
end

local function _pay_rent(game, player_id, tile_id)
  land_actions.execute_pay_rent(game, player_id, tile_id)
  return { ok = true, status = "resolved", effect_id = "pay_rent" }
end

function card_choice.resolve_rent(game, choice, action)
  local meta, meta_error = shared.choice_meta(choice)
  if meta_error then return meta_error end

  local player_id = meta.player_id
  local tile_id = meta.tile_id
  local card_kind = meta.card_kind
  local use_card = shared.option_id_from_action(action) == "use"

  if use_card and _execute_selected_rent_card(game, player_id, tile_id, card_kind) then
    return { ok = true, status = "resolved", effect_id = "pay_rent" }
  end

  local fallback = _try_auto_free_rent(game, player_id, tile_id, card_kind)
  if fallback then return fallback end

  return _pay_rent(game, player_id, tile_id)
end

function card_choice.resolve_tax(game, choice, action)
  local meta, meta_error = shared.choice_meta(choice)
  if meta_error then return meta_error end

  local player_id = meta.player_id
  local use_card = shared.option_id_from_action(action) == "use"

  if use_card then
    land_actions.execute_tax_free_card(game, player_id)
    return { ok = true, status = "resolved", effect_id = "tax_free" }
  end

  land_actions.execute_pay_tax(game, player_id)
  return { ok = true, status = "resolved", effect_id = "pay_tax" }
end

return card_choice

