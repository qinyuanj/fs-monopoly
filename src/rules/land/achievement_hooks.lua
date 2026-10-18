local rent_resolver = require("src.rules.land.rent_resolver")
local achievement_progress = require("src.rules.ports.achievement_progress")

local achievement_hooks = {}

local function _board_of(game)
  return game and game.board or nil
end

local function _tile_index_of(board, tile)
  if board and tile and tile.id ~= nil then
    return board:index_of_tile_id(tile.id)
  end
  return nil
end

function achievement_hooks.record_contiguous_if_reached(game, player, tile)
  local board = _board_of(game)
  local tile_index = _tile_index_of(board, tile)
  if tile_index == nil then
    return
  end
  local count = rent_resolver.contiguous_count(game, board, tile_index, player.id)
  if count >= 3 then
    achievement_progress.contiguous_lands(game, player)
  end
end

return achievement_hooks

