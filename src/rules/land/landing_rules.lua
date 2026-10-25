local property_value = require("src.rules.commerce.property_value")
local land_events = require("src.rules.land.events")
local achievement_hooks = require("src.rules.land.achievement_hooks")
local item_ids = require("src.config.gameplay.item_ids")
local inventory = require("src.rules.items.inventory")
local rent_resolver = require("src.rules.land.rent_resolver")
local rent_payment = require("src.rules.land.rent_payment")
local tax_rules = require("src.rules.land.tax_rules")
local achievement_progress = require("src.rules.ports.achievement_progress")
local number_utils = require("src.foundation.number")

local land_rules = {}
land_rules.safe_tile_state = rent_resolver.safe_tile_state
land_rules.resolve_rent_owner = rent_resolver.resolve_rent_owner
land_rules.contiguous_rent = rent_resolver.contiguous_rent
land_rules.contiguous_count = rent_resolver.contiguous_count
land_rules.contiguous_breakdown = rent_resolver.contiguous_breakdown

local function _resolve_player_and_tile(game, player_id, tile_id)
  local player = game:find_player_by_id(player_id)
  local tile = game.board:get_tile_by_id(tile_id)
  return player, tile
end

local function _resolve_owner(game, owner_id)
  if not owner_id then
    return nil
  end
  return game:find_player_by_id(owner_id)
end

function land_rules.execute_strong_card(game, player_id, tile_id)
  local player, tile = _resolve_player_and_tile(game, player_id, tile_id)
  local st = land_rules.safe_tile_state(game, tile)
  local owner = _resolve_owner(game, st.owner_id)
  assert(owner ~= nil, "missing owner")

  local total_value = property_value.total_invested(tile, st.level)
  if game:player_cash(player) < total_value then
    return { ok = false, reason = "insufficient_balance" }
  end
  -- 「持卡」不变量归 inventory:consume 缺卡时自己 assert,有卡时恒返回 true。
  -- 外层再包一层 assert 只是把同一个不变量写两遍(与 tax_rules 同型)。
  inventory.consume(player, item_ids.strong)
  game:transfer_player_cash(player, owner, total_value)
  game:set_tile_owner(tile, player.id)
  game:set_player_property(owner, tile.id, false)
  game:set_player_property(player, tile.id, true)
  achievement_progress.item_used(game, player)
  achievement_progress.cash_received(game, owner, total_value)
  achievement_progress.land_purchased(game, player)
  achievement_hooks.record_contiguous_if_reached(game, player, tile)
  return land_events.build("strong_card_used", {
    player = player,
    owner = owner,
    tile = tile,
    amount = total_value,
    text = player.name .. " 使用强征卡，支付 " .. number_utils.format_integer_part(total_value) .. " 强制购入 " .. tile.name,
  })
end

function land_rules.execute_free_card(game, player_id, tile_id)
  local player, tile = _resolve_player_and_tile(game, player_id, tile_id)
  inventory.consume(player, item_ids.free_rent)
  achievement_progress.item_used(game, player)
  return land_events.build("free_rent_used", {
    player = player,
    tile = tile,
    text = player.name .. " 出示免费卡，免租 " .. tile.name,
  })
end

land_rules.execute_pay_rent = rent_payment.execute_pay_rent
land_rules.execute_tax_free_card = tax_rules.execute_tax_free_card
land_rules.execute_pay_tax = tax_rules.execute_pay_tax

return land_rules

