-- board.land_neighbors 的唯一所有者：由 board.map.neighbors 投影出的「只含 land」邻接表。
--
-- 这个缓存槽同时被 src/rules/land/rent_resolver（同色连片租金）和
-- src/ui/view/contiguous_count（连片数视图）读取。两边各自懒构建时,谁先跑谁写,
-- 另一边直接复用对方的结果——不变量被推导了两次却没有主人。此处收敛为单一构建者,
-- 于是「键和值都只是 land 地块 id」这条不变量只有一个落点。
--
-- 依赖方向：state 是内层,rules 与 ui 都可以向内依赖它,因此 ui 无需 require rules
-- 即可共享同一份投影(ui_no_rules 仍然成立)。
--
-- board 以 read seam 的形式鸭子类型传入,只要求 path / map.neighbors / get_tile_by_id。

local land_adjacency = {}

local function _land_neighbor_ids(board, neighbors, tile_id)
  local list = {}
  for _, next_id in pairs(neighbors[tile_id] or {}) do
    local next_tile = board:get_tile_by_id(next_id)
    if next_tile and next_tile.type == "land" then
      list[#list + 1] = next_id
    end
  end
  return list
end

local function _build(board, neighbors)
  local land_neighbors = {}
  for _, tile in ipairs(board.path or {}) do
    if tile and tile.type == "land" then
      land_neighbors[tile.id] = _land_neighbor_ids(board, neighbors, tile.id)
    end
  end
  board.land_neighbors = land_neighbors
  return land_neighbors
end

---视图接缝用：board 可能是不含 map 的局部投影,此时退化为空邻接表。
function land_adjacency.ensure(board)
  if board.land_neighbors then
    return board.land_neighbors
  end
  local neighbors = board.map and board.map.neighbors
  if neighbors == nil then
    return {}
  end
  return _build(board, neighbors)
end

local function _is_land(tile)
  return tile and tile.type == "land"
end

---缺 map.neighbors 或缺某块 land 的邻居即刻失败,返回校验通过的邻接源表。
local function _require_complete_neighbors(board)
  assert(board.map ~= nil and board.map.neighbors ~= nil, "missing board.map.neighbors")
  local neighbors = board.map.neighbors
  for _, tile in ipairs(board.path or {}) do
    if _is_land(tile) then
      assert(neighbors[tile.id] ~= nil, "missing neighbors: " .. tostring(tile.id))
    end
  end
  return neighbors
end

---领域用：额外要求棋盘是完整的。
---前置检查只在缓存冷启时跑一次,命中缓存的调用不付代价。
function land_adjacency.ensure_complete(board)
  if board.land_neighbors then
    return board.land_neighbors
  end
  return _build(board, _require_complete_neighbors(board))
end

return land_adjacency

