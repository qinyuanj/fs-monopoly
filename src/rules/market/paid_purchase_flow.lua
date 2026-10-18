local paid_purchase_flow = {}

local IN_FLIGHT_FIELD = "_market_paid_in_flight"
local IN_FLIGHT_TIMEOUT = 12.0

local function _in_flight_key(player_id, product_id)
  return tostring(player_id) .. ":" .. tostring(product_id)
end

function paid_purchase_flow.clear_in_flight(game, player, entry)
  local map = game[IN_FLIGHT_FIELD]
  if map then
    map[_in_flight_key(player.id, entry.product_id)] = nil
  end
end

local function _ensure_in_flight_map(game)
  local in_flight = game[IN_FLIGHT_FIELD]
  if not in_flight then
    in_flight = {}
    game[IN_FLIGHT_FIELD] = in_flight
  end
  return in_flight
end

local function _reject_in_flight_purchase(player, entry)
  local choice_feedback = require("src.rules.market.choice").feedback
  choice_feedback.emit_buy_failed(player, entry, "purchase_in_flight", player.name .. " 正在购买中，请稍候")
  return { ok = false, reason = "purchase_in_flight" }
end

local function _fail_paid_purchase_start(player, entry, product_id, reason)
  local logger = require("src.foundation.log")
  local choice_feedback = require("src.rules.market.choice").feedback
  local failed_reason = reason or "paid_purchase_start_failed"
  logger.warn(
    "market paid purchase blocked:",
    "product_id=" .. tostring(product_id),
    "name=" .. tostring(entry.name or ""),
    "reason=" .. tostring(reason or "unknown")
  )
  choice_feedback.emit_buy_failed(player, entry, failed_reason, player.name .. " 购买通道暂不可用")
  return { ok = false, reason = failed_reason }
end

local function _schedule_in_flight_clear(game, key)
  local runtime_ports = require("src.foundation.ports.runtime_ports")
  runtime_ports.schedule(IN_FLIGHT_TIMEOUT, function()
    local map = game[IN_FLIGHT_FIELD]
    if map then
      map[key] = nil
    end
  end)
end

function paid_purchase_flow.handle(game, player, entry, product_id, setup_for_game)
  local in_flight = _ensure_in_flight_map(game)
  local key = _in_flight_key(player.id, product_id)
  if in_flight[key] then
    return _reject_in_flight_purchase(player, entry)
  end
  in_flight[key] = true

  setup_for_game(game)
  local paid_purchase_gateway = require("src.rules.ports.paid_purchase")
  local ok_start, reason = paid_purchase_gateway.start(game, player, entry)
  if not ok_start then
    in_flight[key] = nil
    return _fail_paid_purchase_start(player, entry, product_id, reason)
  end

  _schedule_in_flight_clear(game, key)

  return {
    ok = true,
    kind = entry.kind,
    product_id = product_id,
    deferred_fulfillment = true,
  }
end

return paid_purchase_flow

