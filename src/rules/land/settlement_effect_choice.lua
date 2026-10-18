local effect_runner = require("src.rules.effects.runner")
local intent_output_port = require("src.rules.ports.intent_output")
local landing_defs = require("src.rules.land.landing_defs")
local tables = require("src.foundation.tables")
local shared = require("src.rules.land.settlement_shared")

local effect_choice = {}

local function _find_effect_by_id(effect_id)
  for _, effect_definition in ipairs(landing_defs) do
    if effect_definition.id == effect_id then
      return effect_definition
    end
  end
  return nil
end

local function _option_id(option)
  return type(option) == "table" and option.id or option
end

local function _same_option(current, option_id)
  return current == option_id or tostring(current) == tostring(option_id)
end

local function _options_of(choice)
  return choice.options or {}
end

local function _option_is_offered(choice, option_id)
  if choice == nil or option_id == nil then
    return false
  end
  for _, option in ipairs(_options_of(choice)) do
    if _same_option(_option_id(option), option_id) then
      return true
    end
  end
  return false
end

local function _landing_optional_effect_id(action)
  local effect_id = shared.option_id_from_action(action)
  if effect_id == nil or effect_id == "" then
    return nil, shared.reject("missing_landing_option")
  end
  return effect_id
end

local function _validate_landing_option(choice, meta, effect_id)
  if meta.effect_ids and not tables.contains(meta.effect_ids, effect_id) then
    return shared.reject("landing_option_not_offered")
  end
  if not _option_is_offered(choice, effect_id) then
    return shared.reject("landing_option_not_offered")
  end
  return nil
end

local function _resolve_landing_effect(effect_id)
  local target_effect = _find_effect_by_id(effect_id)
  if target_effect == nil then
    return nil, shared.reject("landing_effect_not_found")
  end
  return target_effect
end

local function _resolve_landing_effect_target(choice, action)
  local effect_id, effect_id_error = _landing_optional_effect_id(action)
  if effect_id_error then return nil, effect_id_error end

  local meta, meta_error = shared.choice_meta(choice)
  if meta_error then return nil, meta_error end

  local option_error = _validate_landing_option(choice, meta, effect_id)
  if option_error then return nil, option_error end

  local target_effect, effect_error = _resolve_landing_effect(effect_id)
  if effect_error then return nil, effect_error end

  return {
    effect_id = effect_id,
    meta = meta,
    target_effect = target_effect,
  }
end

local function _resolve_landing_effect_actor_tile(game, meta)
  local player, player_error = shared.resolve_choice_player(game, meta)
  if player_error then return nil, nil, player_error end

  local tile, tile_error = shared.resolve_choice_tile(game, player, meta)
  if tile_error then return nil, nil, tile_error end

  return player, tile
end

local function _execute_landing_optional_target(game, target, player, tile)
  local result = effect_runner.execute(
    target.target_effect,
    player,
    tile,
    shared.build_game_ctx(game, target.meta.move_result, "wait_choice")
  )
  intent_output_port.dispatch(game, result.result or result)
  if result.ok ~= true then
    return shared.reject(result.reason or "landing_effect_blocked")
  end
  return {
    ok = true,
    status = "resolved",
    effect_id = target.effect_id,
    result = result.result,
  }
end

function effect_choice.resolve(game, choice, action)
  local target, target_error = _resolve_landing_effect_target(choice, action)
  if target_error then return target_error end

  local player, tile, player_tile_error = _resolve_landing_effect_actor_tile(game, target.meta)
  if player_tile_error then return player_tile_error end

  return _execute_landing_optional_target(game, target, player, tile)
end

effect_choice._M_test = {
  _option_is_offered = _option_is_offered,
}

return effect_choice

