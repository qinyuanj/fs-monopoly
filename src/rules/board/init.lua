local Class = require("src.foundation.class")

---棋盘管理类，负责路径、地块和分支的管理
local board = Class("Board")

local direction = require("src.rules.board.direction")

function board:init(data)
  local tile_lookup = data.tile_lookup
  local path = data.path

  local index_by_id = {}
  for idx, tile in ipairs(path) do
    index_by_id[tile.id] = idx
  end

  self.path = path
  self.tile_lookup = tile_lookup
  self.branches = data.branches
  self.index_by_id = index_by_id
  self.map = data.map
  self.overlays = data.overlays
end

function board:length()
  return #self.path
end

function board:index_of_tile_id(id)
  return self.index_by_id[id]
end

function board:get_tile(index)
  return self.path[index]
end

function board:get_tile_by_id(id)
  return self.tile_lookup[id]
end

function board:find_first_by_type(tile_type)
  for idx, tile in ipairs(self.path) do
    if tile.type == tile_type then
      return idx, tile
    end
  end
  return nil, nil
end

---获取棋盘覆盖物表（包含roadblocks和mines）
function board:get_overlays()
  return self.overlays
end

function board:place_roadblock(index)
  self.overlays.roadblocks = self.overlays.roadblocks or {}
  self.overlays.roadblocks[index] = true
end

function board:has_roadblock(index)
  return self.overlays.roadblocks[index] and true or false
end

function board:clear_roadblock(index)
  self.overlays.roadblocks[index] = nil
end

function board:place_mine(index, data)
  self.overlays.mines = self.overlays.mines or {}
  if data == nil then
    self.overlays.mines[index] = true
    return
  end
  local mine = {}
  for key, value in pairs(data) do
    mine[key] = value
  end
  self.overlays.mines[index] = mine
end

function board:has_mine(index)
  return self.overlays.mines[index] and true or false
end

function board:get_mine(index)
  return self.overlays.mines[index]
end

function board:clear_mine(index)
  self.overlays.mines[index] = nil
end

function board:clear_all(index)
  self:clear_roadblock(index)
  self:clear_mine(index)
end


---单步落点：分支格按奇偶走 odd/even，否则顺延一格
local function _advance_one_step(self, current, branch_parity)
  local branch = self.branches[current]
  if branch and branch_parity then
    if branch_parity % 2 == 1 then
      return branch.odd
    end
    return branch.even
  end
  return current + 1
end

---按步数推进棋盘位置（考虑分支和绕圈）
-- 行为测试公共接缝：test_item 的分支落点与跨起点场景通过此入口验证导航结果。
function board:advance(index, steps, branch_parity)
  local length = self:length()
  if length == 0 then
    return index, 0
  end
  local current = index
  local passed_start = 0
  for _ = 1, steps do
    current = _advance_one_step(self, current, branch_parity)
    if current > length then
      current = current - length
      passed_start = passed_start + 1
    end
  end
  return current, passed_start
end

---根据朝向向前移动一步（用于精确导航）
---第三返回值表示"落点后的下一步前进朝向"，不是刚刚走过来的那一步方向。
function board:step_forward_by_facing(current_index, facing, parity)
  local map = self.map
  local step_context = direction.normalize_forward_step_context(parity)

  local current_tile = self:get_tile(current_index)
  assert(current_tile ~= nil, "missing current tile: " .. tostring(current_index))
  local current_id = current_tile.id
  local neigh = map.neighbors[current_id]
  local next_id, entered_inner = direction.resolve_forward_next_id(
    map,
    current_id,
    neigh,
    facing,
    step_context.parity,
    not step_context.entered_inner,
    step_context.skip_entry_on_tile_id
  )

  assert(next_id ~= nil, "missing next tile id from: " .. tostring(current_id))

  local next_index = self:index_of_tile_id(next_id)
  assert(next_index ~= nil, "missing next tile index: " .. tostring(next_id))
  local passed_start = 0
  if next_id == map.start_id then
    passed_start = 1
  end
  local travel_dir = map.direction(current_id, next_id)
  local next_step_context = {
    parity = step_context.parity,
    entered_inner = step_context.entered_inner or entered_inner,
  }
  local next_facing = direction.resolve_forward_facing(map, next_id, travel_dir, next_step_context)
  return next_index, passed_start, next_facing, entered_inner
end

---根据朝向向后移动一步
---第三返回值表示"落点后的下一步前进朝向"，供后续继续后退时取反使用。
function board:step_backward_by_facing(current_index, facing)
  local map = self.map

  local current_tile = self:get_tile(current_index)
  assert(current_tile ~= nil, "missing current tile: " .. tostring(current_index))
  local current_id = current_tile.id
  local neigh = map.neighbors[current_id]

  local next_result = direction.resolve_backward_next_source(map, current_id, neigh, facing)
  local next_id = next_result.next_id

  assert(next_id ~= nil, "missing prev tile id from: " .. tostring(current_id))

  local next_index = self:index_of_tile_id(next_id)
  assert(next_index ~= nil, "missing prev tile index: " .. tostring(next_id))
  local passed_start = 0
  if next_id == map.start_id then
    passed_start = 1
  end
  local next_facing = map.direction(next_id, current_id)
  return next_index, passed_start, next_facing
end

board._M_test = direction._M_test

return board

