local land_actions = {}
local land_events = require("src.rules.land.events")
local land_rules = require("src.rules.land.landing_rules")
land_actions.safe_tile_state = land_rules.safe_tile_state

function land_actions.resolve_rent_owner(game, tile, state_fn)
  local owner, st, skip = land_rules.resolve_rent_owner(game, tile, state_fn)
  if skip and skip.reason == "mountain" then
    land_events.apply(game, {
      ok = false,
      event = "rent_skipped_mountain",
      payload = {
        owner = skip.owner,
        tile = tile,
        text = skip.owner.name .. " 在深山，租金不收取",
      },
    })
    return nil, st
  end
  return owner, st
end

local function _execute_and_apply(rule_fn, game, ...)
  local result = rule_fn(game, ...)
  if result and result.ok then
    land_events.apply(game, result)
  end
  return result and result.ok == true
end

function land_actions.execute_strong_card(game, player_id, tile_id)
  return _execute_and_apply(land_rules.execute_strong_card, game, player_id, tile_id)
end

function land_actions.execute_free_card(game, player_id, tile_id)
  return _execute_and_apply(land_rules.execute_free_card, game, player_id, tile_id)
end

local function _mountain_skipped(result)
  return result ~= nil and result.event == "rent_skipped_mountain"
end

local function _ok_result(result)
  return result ~= nil and result.ok
end

function land_actions.execute_pay_rent(game, player_id, tile_id)
  local result = land_rules.execute_pay_rent(game, player_id, tile_id)
  if _mountain_skipped(result) then
    land_events.apply(game, result)
    return false
  end
  if _ok_result(result) then
    land_events.apply(game, result)
  end
  return result and result.ok == true
end

function land_actions.execute_tax_free_card(game, player_id)
  return _execute_and_apply(land_rules.execute_tax_free_card, game, player_id)
end

function land_actions.execute_pay_tax(game, player_id)
  return _execute_and_apply(land_rules.execute_pay_tax, game, player_id)
end

return land_actions

