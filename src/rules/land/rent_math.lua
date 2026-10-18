-- 连片 BFS 本身住在 src.state.land_component（领域与视图共用同一条走法）；
-- 这里只负责租金语义：解析每块地的主人与租金,并把同主连片折叠成租金和。

local land_component = require("src.state.land_component")

local rent_math = {}

local function _validate_contiguous_args(start_tile_id, owner_id, neighbors_by_id, resolve_owner_and_rent)
  assert(start_tile_id ~= nil, "missing start_tile_id")
  assert(owner_id ~= nil, "missing owner_id")
  assert(neighbors_by_id ~= nil, "missing neighbors_by_id")
  assert(resolve_owner_and_rent ~= nil, "missing resolve_owner_and_rent")
end

-- 领域侧的邻接是完整的：走到哪块地都必须有邻居表,缺了就是棋盘数据坏了。
local function _strict_neighbors_of(neighbors_by_id)
  return function(tile_id)
    local neighbors = neighbors_by_id[tile_id]
    assert(neighbors ~= nil, "missing neighbors: " .. tostring(tile_id))
    return neighbors
  end
end

function rent_math.compute_contiguous_rent(start_tile_id, owner_id, neighbors_by_id, resolve_owner_and_rent)
  _validate_contiguous_args(start_tile_id, owner_id, neighbors_by_id, resolve_owner_and_rent)

  -- 每块地的租金在 BFS 判主时顺手记下,连片定下来后再按 component 顺序折叠。
  local rent_by_id = {}
  local component = land_component.same_owner(start_tile_id, owner_id, function(tile_id)
    local current_owner, current_rent = resolve_owner_and_rent(tile_id)
    rent_by_id[tile_id] = current_rent or 0
    return current_owner
  end, _strict_neighbors_of(neighbors_by_id))

  local rent_sum = 0
  local rents = {}
  for i, tile_id in ipairs(component) do
    rents[i] = rent_by_id[tile_id]
    rent_sum = rent_sum + rents[i]
  end

  return rent_sum, component, rents
end

return rent_math

