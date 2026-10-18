local choice_registry_module = require("src.rules.choice.registry")
local chance_handlers = require("src.rules.chance.handlers")
local item_registry_module = require("src.rules.items.registry")
local choice_handler_factory = require("src.rules.choice_handlers.factory")
local effect_registry_module = require("src.rules.effects.registry")
local choice_resolver = require("src.rules.choice.resolver")
local land_executors = require("src.rules.land.executors")
local item_phase = require("src.rules.items.phase")
local item_use_flow = require("src.rules.items.use_flow")
local market_effects = require("src.rules.market.effects")

local bootstrap = {}

local function _build_choice_helpers()
  return choice_resolver.helpers({
    begin_item_use = function(game, player, item_id, context)
      return item_use_flow.begin_item_use(game, player and player.id or nil, item_id, context)
    end,
    resolve_item_use_choice = item_use_flow.resolve_item_use_choice,
    finish_active_item_phase = function(game)
      local phase = game.turn.item_phase_active
      if phase and phase ~= "" then
        item_phase.finish(game, phase)
      end
    end,
  })
end

local function _build_choice_groups()
  local helpers = _build_choice_helpers()
  return {
    choice_handler_factory.build_landing_optional_handlers(helpers),
    choice_handler_factory.build_land_handlers(helpers),
    choice_handler_factory.build_item_handlers(helpers),
    choice_handler_factory.build_market_handlers(helpers),
  }
end

local function _build_effect_groups()
  return {
    land_executors.executors,
    market_effects.executors,
  }
end

function bootstrap.create_registries()
  local registries = {
    items = item_registry_module:new(),
    choices = choice_registry_module:new(),
    chances = chance_handlers.build(),
    effects = effect_registry_module:new(),
  }

  registries.items:register_defaults()
  registries.choices:register_defaults(_build_choice_groups())
  registries.effects:register_defaults(_build_effect_groups())

  return registries
end

return bootstrap

