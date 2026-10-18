local number_utils = require("src.foundation.number")

local pricing = {}

local function _max_level(tile)
  local costs = tile.upgrade_costs
  if type(costs) == "table" then
    return #costs
  end
  return 0
end

pricing.max_level = _max_level

local function _purchase_price(tile)
  return tile.price
end

local function _level_indexed(tile, field, level)
  local arr = tile[field]
  if type(arr) ~= "table" then
    return 0
  end
  return arr[(level or 0) + 1] or 0
end

function pricing.upgrade_cost(tile, level)
  return _level_indexed(tile, "upgrade_costs", level)
end

function pricing.rent_for_level(tile, level)
  if tile and tile.price ~= nil then
    local normalized_level = number_utils.clamp(level or 0, 0, _max_level(tile))
    return math.floor((tile.price * (2 ^ normalized_level)) * 0.5)
  end
  return _level_indexed(tile, "rents", level)
end

function pricing.total_invested(tile, level)
  local total = _purchase_price(tile)
  local costs = tile.upgrade_costs
  if type(costs) ~= "table" then
    return total
  end
  for i = 1, level do
    total = total + (costs[i] or 0)
  end
  return total
end

return pricing

