local target_direction = {}

function target_direction.manhattan_distance(a, b)
  return math.abs(a.row - b.row) + math.abs(a.col - b.col)
end

-- Direction is a boolean decision: a tile is either behind the target
-- (backward) or everything else falls into the forward queue. Co-located
-- tiles (zero delta on both axes) count as forward.
-- 共点格(dr==dc==0)时 dominant==0,`dominant > 0` 与
-- `dominant >= 0 and (dr ~= 0 or dc ~= 0)` 逐位等价(共点 ⟺ dominant==0),
-- 共点格因此落入 forward 队列。
local function _geometry_is_backward(start_tile, tile)
  local dr = tile.row - start_tile.row
  local dc = tile.col - start_tile.col
  local dominant = math.abs(dr) > math.abs(dc) and dr or dc
  return dominant > 0
end

local function _is_backward(idx, fwd_set, bwd_set, start_tile, board)
  if fwd_set[idx] then return false end
  if bwd_set[idx] then return true end
  local tile = board:get_tile(idx)
  if start_tile == nil or tile == nil then return false end
  return _geometry_is_backward(start_tile, tile)
end

function target_direction.build_queues(by_dist, max_dist, board, fwd, bwd, start_tile)
  local backward_queue = {}
  local forward_queue = {}
  for dist = 1, max_dist do
    for _, idx in ipairs(by_dist[dist] or {}) do
      if _is_backward(idx, fwd.set, bwd.set, start_tile, board) then
        backward_queue[#backward_queue + 1] = idx
      else
        forward_queue[#forward_queue + 1] = idx
      end
    end
  end
  return backward_queue, forward_queue
end

return target_direction

