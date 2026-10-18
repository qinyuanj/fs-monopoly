local inventory = require("src.rules.items.inventory")

local context = {}

local function _find_by_id(game, actor_id)
  if game and type(game.find_player_by_id) == "function" then
    return game:find_player_by_id(actor_id)
  end
  return nil
end

local function _find_linear(game, actor_id)
  for _, player in ipairs(game and game.players or {}) do
    if player.id == actor_id then
      return player
    end
  end
  return nil
end

function context.resolve_actor(game, actor_id)
  if type(actor_id) == "table" then
    return actor_id
  end
  return _find_by_id(game, actor_id) or _find_linear(game, actor_id)
end

function context.count_item(player, item_id)
  local count = 0
  for _, item in ipairs(inventory.items(player)) do
    if item ~= false and item.id == item_id then
      count = count + 1
    end
  end
  return count
end

return context

