-- 同主连片的视图口径：把「哪些地连成一片」翻译成视图要的计数 / 租金和。
-- 输入全部来自 board 读接缝,这里不需要任何领域知识。
--
-- 邻接表与连片走法都不在这里：board.land_neighbors 由 src.state.land_adjacency 独家拥有,
-- BFS 由 src.state.land_component 独家拥有,rules 侧的租金解析吃的是同一份投影和同一条走法。
-- state 是内层,ui 向内依赖它不违反 ui_no_rules。

local land_adjacency = require("src.state.land_adjacency")
local land_component = require("src.state.land_component")

local M = {}

local function _owner_via_get_tile(board, tile_id)
  if type(board.get_tile_by_id) == "function" then
    local tile = board:get_tile_by_id(tile_id)
    return tile and tile.owner_id or nil
  end
  return nil
end

local function _owner_of(board, tile_id)
  -- lookup 命中即返回即使 owner_id 为 nil，不回退 get_tile_by_id。
  if board.tile_lookup and board.tile_lookup[tile_id] then
    return board.tile_lookup[tile_id].owner_id
  end
  return _owner_via_get_tile(board, tile_id)
end

-- 视图拿到的可能是不含完整 map 的局部投影,缺邻居的地块退化为孤岛而不是报错。
local function _bfs_component(neighbors, board, start_tile_id, owner_id)
  return land_component.same_owner(start_tile_id, owner_id, function(tile_id)
    return _owner_of(board, tile_id)
  end, function(tile_id)
    return neighbors[tile_id] or {}
  end)
end

-- 行为测试公共查询：连片视图场景以独立 flood-fill 真源核对单地块计数和批量投影。
function M.for_tile(board, tile_id, owner_id)
  if not (board and tile_id ~= nil and owner_id ~= nil) then
    return 0
  end
  if _owner_of(board, tile_id) ~= owner_id then
    return 0
  end
  local neighbors = land_adjacency.ensure(board)
  return #_bfs_component(neighbors, board, tile_id, owner_id)
end

-- out[tile_id] 非空说明该地块已被前一个连通块收编，不必再从它出发 BFS。
local function _is_unvisited_owned_land(tile, owner_id, out, tile_id)
  return tile ~= nil and tile.type == "land" and tile.owner_id == owner_id and out[tile_id] == nil
end

local function _assign_component(out, component, value)
  for _, cid in ipairs(component) do
    out[cid] = value
  end
end

local function _map_ready(board, owner_id)
  return board and owner_id ~= nil
end

local function _build_owner_map(board, owner_id, reducer)
  local out = {}
  if not _map_ready(board, owner_id) then
    return out
  end
  local lookup = board.tile_lookup or {}
  local neighbors = land_adjacency.ensure(board)
  for tile_id, tile in pairs(lookup) do
    if _is_unvisited_owned_land(tile, owner_id, out, tile_id) then
      local component = _bfs_component(neighbors, board, tile_id, owner_id)
      _assign_component(out, component, reducer(lookup, component, board))
    end
  end
  return out
end

-- Build a tile_id -> count map for every land tile owned by owner_id.
-- One BFS per connected component (vs one per tile when calling for_tile in a loop).
function M.build_for_owner(board, owner_id)
  return _build_owner_map(board, owner_id, function(_, component)
    return #component
  end)
end

local function _component_tile(lookup, board_ref, cid)
  return lookup[cid] or (type(board_ref.get_tile_by_id) == "function" and board_ref:get_tile_by_id(cid) or nil)
end

function M.build_rent_for_owner(board, owner_id, rent_for_tile)
  if type(rent_for_tile) ~= "function" then
    return {}
  end
  return _build_owner_map(board, owner_id, function(lookup, component, board_ref)
    local rent_sum = 0
    for _, cid in ipairs(component) do
      rent_sum = rent_sum + (rent_for_tile(_component_tile(lookup, board_ref, cid), cid) or 0)
    end
    return rent_sum
  end)
end

return M

