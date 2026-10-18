local achievement_progress = {}

local configured_port = nil

local function _resolve_port(game)
  if game and type(game.achievement_progress_port) == "table" then
    return game.achievement_progress_port
  end
  return configured_port
end

local function _call(game, method_name, ...)
  local port = _resolve_port(game)
  local fn = port and port[method_name] or nil
  if type(fn) ~= "function" then
    return false
  end
  local ok, result = pcall(fn, game, ...)
  if not ok then
    return false
  end
  return result == true
end

function achievement_progress.configure(port)
  assert(port == nil or type(port) == "table", "invalid achievement progress port")
  configured_port = port
end

function achievement_progress.reset_for_tests()
  configured_port = nil
end

function achievement_progress.game_won(game, player)
  return _call(game, "game_won", player)
end

function achievement_progress.land_purchased(game, player)
  return _call(game, "land_purchased", player)
end

function achievement_progress.cash_received(game, player, amount)
  return _call(game, "cash_received", player, amount)
end

function achievement_progress.tax_paid(game, player, amount)
  return _call(game, "tax_paid", player, amount)
end

function achievement_progress.item_used(game, player)
  return _call(game, "item_used", player)
end

function achievement_progress.chance_card_drawn(game, player)
  return _call(game, "chance_card_drawn", player)
end

function achievement_progress.market_item_bought(game, player)
  return _call(game, "market_item_bought", player)
end

function achievement_progress.building_upgraded(game, player, level)
  return _call(game, "building_upgraded", player, level)
end

function achievement_progress.deity_attached(game, player, deity_type)
  return _call(game, "deity_attached", player, deity_type)
end

function achievement_progress.location_effect(game, player, effect)
  return _call(game, "location_effect", player, effect)
end

function achievement_progress.contiguous_lands(game, player)
  return _call(game, "contiguous_lands", player)
end

function achievement_progress.monster_demolished_building(game, player)
  return _call(game, "monster_demolished_building", player)
end

function achievement_progress.typhoon_demolished_building(game, player)
  return _call(game, "typhoon_demolished_building", player)
end

function achievement_progress.skin_equipped(game, role_id, skin)
  return _call(game, "skin_equipped", role_id, skin)
end

return achievement_progress

