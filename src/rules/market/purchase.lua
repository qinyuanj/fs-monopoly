local logger = require("src.foundation.log")
local number_utils = require("src.foundation.number")
local paid_purchase_gateway = require("src.rules.ports.paid_purchase")
local market_query = require("src.rules.market.query")
local market_choice = require("src.rules.market.choice")
local paid_purchase_flow = require("src.rules.market.paid_purchase_flow")
local fulfillment = require("src.rules.market.purchase_fulfillment")

local query_context = market_query.context
local choice_feedback = market_choice.feedback
local choice_session = market_choice.session

local policy = {}

function policy.validate_entry(game, player, entry)
  local product_id = entry.product_id
  if not query_context.entry_market_enabled(entry) then
    return {
      ok = false,
      reason = "disabled",
      body = player.name .. " 该商品暂不可购买",
    }
  end
  if entry.kind ~= "item" then
    return {
      ok = false,
      reason = "unsupported_kind",
      body = player.name .. " 该商品类型暂不支持购买",
    }
  end
  local remaining = query_context.remaining_global_limit(game, product_id)
  if remaining <= 0 then
    return {
      ok = false,
      reason = "sold_out",
      body = player.name .. " 该商品已售罄",
    }
  end
  return { ok = true }
end

local local_purchase = {}

function local_purchase.execute(game, player, entry)
  local product_id = entry.product_id
  local price = query_context.entry_price(entry)
  local currency = query_context.entry_currency(entry)
  -- 非付费币种只允许默认金币：未知币种在读扣余额前硬失败，不得静默按金币成交。
  query_context.assert_cash_currency(currency)

  if game:player_cash(player) < price then
    choice_feedback.emit_buy_failed(player, entry, "insufficient_balance", player.name .. " 余额不足")
    return { ok = false, reason = "insufficient_balance", option_id = product_id }
  end

  local result = fulfillment.apply(game, player, entry, {
    skip_charge = false,
    price = price,
    currency = currency,
    priced_text = true,
  })
  if not result.ok then
    choice_feedback.emit_buy_failed(player, entry, result.reason, result.body)
    return { ok = false, reason = result.reason }
  end
  return result
end

local paid_fulfillment = {}

function paid_fulfillment.fulfill_entry(game, player, entry)
  local price = query_context.entry_price(entry)
  local currency = query_context.entry_currency(entry)
  local decision = policy.validate_entry(game, player, entry)
  if not decision.ok then
    choice_feedback.emit_buy_failed(player, entry, decision.reason, decision.body)
    return false
  end

  local result = fulfillment.apply(game, player, entry, {
    skip_charge = true,
    price = price,
    currency = currency,
    priced_text = false,
  })
  if result.ok then
    return true
  end
  choice_feedback.emit_buy_failed(player, entry, result.reason, result.body)
  return false
end

local paid_purchase_callback = {}

function paid_purchase_callback.handle(game, player, entry)
  paid_purchase_flow.clear_in_flight(game, player, entry)
  local ok = paid_fulfillment.fulfill_entry(game, player, entry)
  if ok then
    choice_session.refresh_after_paid_callback(game, player, entry)
  end
  return ok
end

local purchase = {}

function purchase.setup_for_game(game)
  paid_purchase_gateway.setup_for_game(game, paid_purchase_callback.handle)
end

local function _resolve_product_id(product_id)
  local resolved = number_utils.to_integer(product_id)
  if resolved == nil or resolved <= 0 then
    return nil
  end
  return resolved
end

local function _validate_purchase_entry(game, player, entry)
  local decision = policy.validate_entry(game, player, entry)
  if not decision.ok then
    choice_feedback.emit_buy_failed(player, entry, decision.reason, decision.body)
    return false, decision.reason
  end
  return true
end

local function _handle_paid_purchase(game, player, entry, product_id)
  return paid_purchase_flow.handle(game, player, entry, product_id, purchase.setup_for_game)
end

function purchase.execute(game, player, product_id)
  local resolved_product_id = _resolve_product_id(product_id)
  if resolved_product_id == nil then
    logger.warn("invalid market product id:", tostring(product_id))
    return false
  end
  product_id = resolved_product_id

  local entry = query_context.entry_by_id(product_id)
  assert(entry ~= nil, "missing market entry: " .. tostring(product_id))

  local ok, reason = _validate_purchase_entry(game, player, entry)
  if not ok then
    return { ok = false, reason = reason }
  end

  local currency = query_context.entry_currency(entry)
  if query_context.is_paid_currency(currency) then
    return _handle_paid_purchase(game, player, entry, product_id)
  end
  return local_purchase.execute(game, player, entry)
end

return {
  execute = purchase.execute,
  setup_for_game = purchase.setup_for_game,
}

