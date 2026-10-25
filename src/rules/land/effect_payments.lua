local item_ids = require("src.config.gameplay.item_ids")
local event_kinds = require("src.config.gameplay.event_kinds")
local tile_mod = require("src.rules.board.tile")
local land_actions = require("src.rules.land.actions")
local land_choice_specs = require("src.rules.land.choice_specs")
local event_feed = require("src.rules.ports.event_feed")
local inventory = require("src.rules.items.inventory")
local property_value = require("src.rules.commerce.property_value")

local tile_state = tile_mod.get_state

local M = {}

local function _can_pay_rent(ctx)
  local t = ctx.tile
  local player = ctx.player
  assert(t ~= nil, "missing tile")
  if t.type ~= "land" then return false end
  local st = land_actions.safe_tile_state(ctx.game, t)
  return st.owner_id and st.owner_id ~= player.id
end

local function _find_rent_item_indices(player)
  return inventory.find_index(player, item_ids.strong), inventory.find_index(player, item_ids.free_rent)
end

local function _can_use_strong_card(player, strong_idx, total_value, game)
  return strong_idx and game:player_cash(player) >= total_value
end

local function _build_rent_choice_intent(player, tile, card_kind, total_value)
  return {
    waiting = true,
    reason = "rent_choice",
    intent = {
      kind = "need_choice",
      choice_spec = land_choice_specs.rent_prompt(player.id, tile.id, card_kind, total_value, tile.name),
    },
  }
end

local function _consume_pending_free_rent(ctx, player, tile)
  if not ctx.game:consume_pending_free_rent(player) then
    return false
  end
  event_feed.publish(ctx.game, {
    kind = event_kinds.rent_immune,
    text = player.name .. " 使用免费卡，免租 " .. tile.name,
  })
  return true
end

local function _apply_rent_card_or_payment(ctx, player, tile, tile_state_value)
  local total_value = property_value.total_invested(tile, tile_state_value.level)
  local strong_idx, free_idx = _find_rent_item_indices(player)

  if _can_use_strong_card(player, strong_idx, total_value, ctx.game) then
    return _build_rent_choice_intent(player, tile, "strong", total_value)
  end

  if free_idx then
    land_actions.execute_free_card(ctx.game, player.id, tile.id)
    return
  end

  land_actions.execute_pay_rent(ctx.game, player.id, tile.id)
end

local function _apply_pay_rent(ctx)
  local t = ctx.tile
  local player = ctx.player
  assert(t ~= nil and t.type == "land", "invalid land tile")
  local owner, st = land_actions.resolve_rent_owner(ctx.game, t, tile_state)
  if not owner then return end

  if _consume_pending_free_rent(ctx, player, t) then
    return
  end

  return _apply_rent_card_or_payment(ctx, player, t, st)
end

local function _can_tax(ctx)
  assert(ctx.tile ~= nil, "missing tile")
  return ctx.tile.type == "tax"
end

local function _apply_tax(ctx)
  local player = ctx.player

  if ctx.game:consume_pending_tax_free(player) then
    event_feed.publish(ctx.game, {
      kind = event_kinds.tax_immune,
      text = player.name .. " 使用免税卡，本次免税",
    })
    return
  end

  local tax_idx = inventory.find_index(player, item_ids.tax_free)
  if tax_idx then
    return {
      waiting = true,
      reason = "tax_choice",
      intent = {
        kind = "need_choice",
        choice_spec = land_choice_specs.tax_prompt(player.id),
      },
    }
  end

  land_actions.execute_pay_tax(ctx.game, player.id)
end

M.executors = {
  pay_rent = { can_apply = _can_pay_rent, apply = _apply_pay_rent },
  tax = { can_apply = _can_tax, apply = _apply_tax },
}

return M

