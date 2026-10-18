local direction_constants = require("src.rules.board.directions")

local obstacle_clear_tiles = {}

function obstacle_clear_tiles.sorted_forward_dirs(neigh, back_dir)
  local dirs = {}
  for dir, _ in pairs(neigh) do
    if dir ~= back_dir then
      dirs[#dirs + 1] = dir
    end
  end
  table.sort(dirs)
  return dirs
end

function obstacle_clear_tiles.copy_path(src)
  -- 等价于 1..#src 的逐位复制(致密路径数组),化简后无循环下界字面量位点。
  return { table.unpack(src) }
end

local function _clear_obstacles_on_tile(game, state, tile_index, had_rb, had_mine)
  -- 无 cleared_map 去重守卫:唯一调用方 visit_tile 由 obstacle_snapshot
  -- 保证每格只进一次,守卫与字段均无读者(#259 删除)。
  if had_rb then
    game:clear_roadblock(tile_index)
    state.roadblock_cleared = state.roadblock_cleared + 1
  end
  if had_mine then
    game:clear_mine(tile_index)
    state.mine_cleared = state.mine_cleared + 1
  end
  if had_rb or had_mine then
    state.cleared = state.cleared + 1
  end
end

function obstacle_clear_tiles.visit_tile(game, board, state, tile_id, tile_index)
  if not state.obstacle_snapshot[tile_id] then
    local had_rb = board:has_roadblock(tile_index)
    local had_mine = board:has_mine(tile_index)
    state.obstacle_snapshot[tile_id] = (had_rb or had_mine) and "yes" or "no"
    _clear_obstacles_on_tile(game, state, tile_index, had_rb, had_mine)
  end
  return state.obstacle_snapshot[tile_id] == "yes"
end

function obstacle_clear_tiles.next_strict_or_turn(neigh, facing, opposite)
  if neigh[facing] then
    return { facing }
  end
  local back_dir = opposite[facing]
  return obstacle_clear_tiles.sorted_forward_dirs(neigh, back_dir)
end

function obstacle_clear_tiles.resolve_initial_dirs(start_neigh, facing)
  if facing == nil then
    return obstacle_clear_tiles.sorted_forward_dirs(start_neigh, nil)
  end
  if start_neigh[facing] then
    return { facing }
  end
  local back_dir = direction_constants.opposite[facing]
  return obstacle_clear_tiles.sorted_forward_dirs(start_neigh, back_dir)
end

return obstacle_clear_tiles

