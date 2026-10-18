local item_handlers = require("src.rules.choice_handlers.item")
local land_handlers = require("src.rules.choice_handlers.land")
local landing_optional_handlers = require("src.rules.choice_handlers.landing_optional")
local market_handlers = require("src.rules.choice_handlers.market")

local choice_handler_factory = {}

local function _build(handler_module, helpers)
  local registry = {}
  handler_module.register(registry, helpers)
  return registry
end

function choice_handler_factory.build_item_handlers(helpers)
  return _build(item_handlers, helpers)
end

function choice_handler_factory.build_land_handlers(helpers)
  return _build(land_handlers, helpers)
end

function choice_handler_factory.build_landing_optional_handlers(helpers)
  return _build(landing_optional_handlers, helpers)
end

function choice_handler_factory.build_market_handlers(helpers)
  return _build(market_handlers, helpers)
end

return choice_handler_factory

