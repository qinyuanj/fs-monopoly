local property_value = require("src.rules.commerce.property_value")
local tile_mod = require("src.rules.board.tile")

local asset_total = {}

-- Remaining total assets for a player: cash plus the invested value of every
-- land tile they own (purchase price plus per-level upgrade costs).
function asset_total.player_total(game, player)
  local total = game:player_cash(player)
  assert(total ~= nil, "missing player cash")
  for tile_id in pairs(player.properties or {}) do
    local tile = game.board:get_tile_by_id(tile_id)
    assert(tile ~= nil and tile.type == "land", "invalid property tile: " .. tostring(tile_id))
    local st = tile_mod.get_state(game, tile)
    total = total + property_value.total_invested(tile, st.level)
  end
  return total
end

return asset_total

