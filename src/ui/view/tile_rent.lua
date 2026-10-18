local number_utils = require("src.foundation.number")

local tile_rent = {}

local function _max_level(tile)
  local costs = tile and tile.upgrade_costs or nil
  if type(costs) == "table" then
    return #costs
  end
  return 0
end

function tile_rent.for_level(tile, level)
  if tile == nil or tile.price == nil then
    return nil
  end
  local normalized_level = number_utils.clamp(level or 0, 0, _max_level(tile))
  return math.floor((tile.price * (2 ^ normalized_level)) * 0.5)
end

return tile_rent

