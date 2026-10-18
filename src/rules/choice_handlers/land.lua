local land_settlement = require("src.rules.land.settlement")
local landing_result = require("src.rules.choice_handlers.landing_result")

local M = {}

local function _build(helpers)
  local finish_choice = helpers.finish_choice

  local function _handle_landing_choice(game, choice, action)
    local result = land_settlement.resolve_landing_settlement_choice(game, choice, action)
    return landing_result.settle(finish_choice, game, result)
  end

  return {
    rent_card_prompt = {
      required_meta = { "player_id", "tile_id" },
      cancel = { mode = "select_option", option_id = "skip" },
      execute = _handle_landing_choice,
    },
    tax_card_prompt = {
      required_meta = { "player_id" },
      cancel = { mode = "select_option", option_id = "skip" },
      execute = _handle_landing_choice,
    },
  }
end

function M.register(registry, helpers)
  local handlers = _build(helpers)
  for kind, handler in pairs(handlers) do
    registry[kind] = handler
  end
end

return M

