local land_settlement = require("src.rules.land.settlement")
local landing_result = require("src.rules.choice_handlers.landing_result")
local availability = require("src.rules.items.availability")
local logger = require("src.foundation.log")

local M = {}

local function _build(helpers)
  local finish_choice = helpers.finish_choice

  local function _normalize_optional_meta(game, meta, choice_spec)
    local normalized_meta = availability.copy_table(meta)
    availability.normalize_integer_field(normalized_meta, "player_id", choice_spec.kind)
    availability.normalize_integer_field(normalized_meta, "tile_id", choice_spec.kind)
    choice_spec.owner_role_id = choice_spec.owner_role_id or normalized_meta.player_id
    return normalized_meta
  end

  local function _validate_optional_meta(game, meta, choice_spec)
    assert(game:find_player_by_id(meta.player_id), "missing player: " .. tostring(meta.player_id))
    assert(game.board:get_tile_by_id(meta.tile_id), "missing tile: " .. tostring(meta.tile_id))
    if meta.effect_ids ~= nil then
      assert(type(meta.effect_ids) == "table", tostring(choice_spec.kind) .. " requires table meta.effect_ids")
    end
  end

  local function _normalize_optional_action(_, _, action)
    local normalized_action = availability.copy_table(action)
    assert(type(normalized_action.option_id) == "string" and normalized_action.option_id ~= "",
      "landing_optional_effect requires string action.option_id")
    return normalized_action
  end

  local function _handle_optional_landing_effect(game, choice, action)
    local result = land_settlement.resolve_landing_settlement_choice(game, choice, action)
    if result and result.ok == false then
      logger.warn("landing_optional_effect execute blocked:", tostring(result.reason))
    end
    return landing_result.settle(finish_choice, game, result)
  end

  return {
    landing_optional_effect = {
      required_meta = { "player_id", "tile_id" },
      normalize_meta = _normalize_optional_meta,
      meta_validator = _validate_optional_meta,
      normalize_action = _normalize_optional_action,
      execute = _handle_optional_landing_effect,
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

