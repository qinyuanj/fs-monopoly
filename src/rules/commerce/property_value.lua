local property_value = {}

local function _purchase_price(tile)
  assert(tile ~= nil, "missing tile")
  return tile.price or 0
end

local function _upgrade_cost(tile, level)
  assert(tile ~= nil, "missing tile")
  local costs = tile.upgrade_costs or {}
  local next_level = (level or 0) + 1
  return costs[next_level] or 0
end

function property_value.total_invested(tile, level)
  assert(tile ~= nil, "missing tile")
  local total = _purchase_price(tile)
  local max_level = level or 0
  for current_level = 0, max_level - 1 do
    total = total + _upgrade_cost(tile, current_level)
  end
  return total
end

return property_value

