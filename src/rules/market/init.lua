local query = require("src.rules.market.query")
local choice = require("src.rules.market.choice")
local purchase = require("src.rules.market.purchase")
local auto = require("src.rules.market.auto")

local market_service = {
  query = {},
  choice = {},
  purchase = {},
  auto = {},
}

market_service.query.list_available = query.eligibility.list_available
market_service.choice.build = choice.builder.build
market_service.choice.rebuild_pending = choice.session.rebuild_pending
market_service.choice.apply_navigation = choice.session.apply_navigation
market_service.purchase.execute = purchase.execute
market_service.purchase.setup_for_game = purchase.setup_for_game
market_service.auto.execute = auto.execute

return market_service

