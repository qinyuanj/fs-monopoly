local market_catalog = require("src.config.content.market_catalog")
local items_cfg = require("src.config.content.items")
local paid_currency_bridge = require("src.rules.commerce.paid_currency_bridge")
local inventory = require("src.rules.items.inventory")
local paid_purchase_port = require("src.rules.ports.paid_purchase")
local purchase_limit = require("src.rules.market.purchase_limit")

local context = {}

local items_by_id = {}
for _, cfg in ipairs(items_cfg) do
  items_by_id[cfg.id] = cfg
end

local _entries = market_catalog.entries
context.entry_by_id = market_catalog.entry_by_id

function context.entry_name(entry)
  local cfg = items_by_id[entry.product_id]
  if cfg then
    return cfg.name
  end
  if entry.name then
    return entry.name
  end
  return tostring(entry.product_id)
end

function context.entry_price(entry)
  return entry.price or 0
end

local _DEFAULT_ENTRY_CURRENCY = "金币"

function context.entry_currency(entry)
  local currency = entry.currency
  if currency and currency ~= "" then
    return currency
  end
  return _DEFAULT_ENTRY_CURRENCY
end

function context.entry_market_enabled(entry)
  assert(entry ~= nil, "missing market entry")
  return entry.market_enabled ~= false
end

context.is_paid_currency = paid_currency_bridge.is_paid_currency

-- 收银防线：本地读扣路径只认默认金币币种。付费币种或未知币种必须硬失败，
-- 不得静默按金币读扣（保持既有 unsupported currency 的 fail-fast 语义）。
function context.assert_cash_currency(currency)
  assert(not context.is_paid_currency(currency) and currency == _DEFAULT_ENTRY_CURRENCY,
    "unsupported market currency: " .. tostring(currency))
end

function context.try_charge_player(game, player, price, opts)
  game:deduct_player_cash(player, price, opts)
  return true
end

local eligibility = {}

local function _is_market_item(entry)
  return entry ~= nil and entry.kind == "item"
end

-- 与货币、卡槽无关的准入闸门:是商品、已上架、未限购买满(ADR 0080)。
local function _entry_on_offer(game, player, entry)
  if not _is_market_item(entry) then
    return false
  end
  if not context.entry_market_enabled(entry) then
    return false
  end
  return not purchase_limit.is_reached(game, player, entry)
end

-- 付费货币走宿主下单校验,现金货币比 player_cash。
local function _can_afford_entry(game, player, entry)
  local price = context.entry_price(entry)
  local currency = context.entry_currency(entry)
  if context.is_paid_currency(currency) then
    local ok = paid_purchase_port.can_start(game, player, entry)
    return ok == true
  end
  context.assert_cash_currency(currency)
  return game:player_cash(player) >= price
end

-- 只要腾出一格卡槽就能买(ADR 0081):黑市屏购买按钮的显隐依据。
function eligibility.can_buy_with_free_slot(game, player, entry)
  if not _entry_on_offer(game, player, entry) then
    return false
  end
  return _can_afford_entry(game, player, entry)
end

function eligibility.can_buy_entry(game, player, entry)
  return eligibility.can_buy_with_free_slot(game, player, entry) and not inventory.is_full(player)
end

function eligibility.sorted_entries()
  local entries = {}
  for _, entry in ipairs(_entries()) do
    entries[#entries + 1] = entry
  end
  table.sort(entries, function(a, b)
    return (a.order or 0) < (b.order or 0)
  end)
  return entries
end

function eligibility.list_available(player, game)
  local list = {}
  for _, entry in ipairs(eligibility.sorted_entries()) do
    if eligibility.can_buy_entry(game, player, entry) then
      list[#list + 1] = entry
    end
  end
  return list
end

local function _split_entries_by_buyable(player, game)
  local buyable = {}
  local unbuyable = {}
  for _, entry in ipairs(eligibility.sorted_entries()) do
    if eligibility.can_buy_entry(game, player, entry) then
      buyable[#buyable + 1] = entry
    else
      unbuyable[#unbuyable + 1] = entry
    end
  end
  return buyable, unbuyable
end

local function _append_visible_entries(visible, entries, can_buy, limit)
  for _, entry in ipairs(entries) do
    visible[#visible + 1] = { entry = entry, can_buy = can_buy }
    if limit and #visible >= limit then
      return true
    end
  end
  return false
end

eligibility._split_entries_by_buyable = _split_entries_by_buyable
eligibility._append_visible_entries = _append_visible_entries

return {
  context = context,
  eligibility = eligibility,
}

