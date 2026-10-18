local fulfillment = {}

local function _query_context()
  return require("src.rules.market.query").context
end

local function _emit_bought_item(game, payload)
  local monopoly_event = require("src.foundation.events")
  local event_feed = require("src.rules.ports.event_feed")
  local event_kinds = require("src.config.gameplay.event_kinds")

  monopoly_event.emit(monopoly_event.market.bought_item, payload)
  event_feed.publish(game, {
    kind = event_kinds.item_acquired,
    text = payload.text,
  })
end

local function _success_text(player, entry, price, currency, priced)
  local query_context = _query_context()
  local name = query_context.entry_name(entry)
  if priced then
    local number_utils = require("src.foundation.number")
    return player.name .. " 在黑市购买 " .. name .. " 花费 " .. number_utils.format_integer_part(price) .. " " .. currency
  end
  return player.name .. " 在黑市购买 " .. name .. " 成功"
end

local function _charge_if_needed(game, player, price, opts)
  if opts and opts.skip_charge == true then
    return true
  end
  return _query_context().try_charge_player(game, player, price, {
    suppress_cash_receive_anim = true,
  })
end

local function _fulfill_item(game, player, entry, opts)
  local inventory = require("src.rules.items.inventory")
  local query_context = _query_context()
  if inventory.is_full(player) then
    return { ok = false, reason = "inventory_full", body = player.name .. " 卡槽已满" }
  end
  if not _charge_if_needed(game, player, opts.price, opts) then
    return { ok = false, reason = "charge_failed", body = player.name .. " 支付失败" }
  end
  local given = inventory.give(player, entry.product_id, { game = game })
  if given == true then
    require("src.rules.items.gain_reveal").queue(game, player, entry.product_id, { source = "market" })
  end
  query_context.consume_global_limit(game, entry.product_id)
  _emit_bought_item(game, {
    player = player,
    entry = entry,
    price = opts.price,
    currency = opts.currency,
    text = _success_text(player, entry, opts.price, opts.currency, opts.priced_text),
  })
  require("src.rules.ports.achievement_progress").market_item_bought(game, player)
  return {
    ok = true,
    kind = "item",
    product_id = entry.product_id,
    inventory_full_after = inventory.is_full(player),
    fulfilled_now = true,
  }
end

function fulfillment.apply(game, player, entry, opts)
  local resolved_opts = {
    skip_charge = opts and opts.skip_charge == true,
    price = opts and opts.price,
    currency = opts and opts.currency,
    priced_text = opts and opts.priced_text == true,
  }
  return _fulfill_item(game, player, entry, resolved_opts)
end

return fulfillment

