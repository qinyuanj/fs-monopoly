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

--[[ mutate4lua-manifest
version=4
projectHash=6a7efe35451e00fa
scope.0.id=chunk:src/rules/board/init.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=206
scope.0.semanticHash=285d08481fed23f9
scope.1.id=function:board:init
scope.1.kind=function
scope.1.startLine=8
scope.1.endLine=23
scope.1.semanticHash=93e28199e93f6db4
scope.2.id=function:board:length
scope.2.kind=function
scope.2.startLine=25
scope.2.endLine=27
scope.2.semanticHash=85279e1d919e028a
scope.3.id=function:board:index_of_tile_id
scope.3.kind=function
scope.3.startLine=29
scope.3.endLine=31
scope.3.semanticHash=70ade069282003e1
scope.4.id=function:board:get_tile
scope.4.kind=function
scope.4.startLine=33
scope.4.endLine=35
scope.4.semanticHash=70ade069282003e1
scope.5.id=function:board:get_tile_by_id
scope.5.kind=function
scope.5.startLine=37
scope.5.endLine=39
scope.5.semanticHash=70ade069282003e1
scope.6.id=function:board:find_first_by_type
scope.6.kind=function
scope.6.startLine=41
scope.6.endLine=48
scope.6.semanticHash=a119dbe5709833e5
scope.7.id=function:board:get_overlays
scope.7.kind=function
scope.7.startLine=51
scope.7.endLine=53
scope.7.semanticHash=c0484ae42c9068b0
scope.8.id=function:board:place_roadblock
scope.8.kind=function
scope.8.startLine=55
scope.8.endLine=58
scope.8.semanticHash=fbce94eda9508a55
scope.9.id=function:board:has_roadblock
scope.9.kind=function
scope.9.startLine=60
scope.9.endLine=62
scope.9.semanticHash=35209888bd2b57fa
scope.10.id=function:board:clear_roadblock
scope.10.kind=function
scope.10.startLine=64
scope.10.endLine=66
scope.10.semanticHash=4e98fb16b410a74c
scope.11.id=function:board:place_mine
scope.11.kind=function
scope.11.startLine=68
scope.11.endLine=79
scope.11.semanticHash=bd85f10fe547ad6f
scope.12.id=function:board:has_mine
scope.12.kind=function
scope.12.startLine=81
scope.12.endLine=83
scope.12.semanticHash=35209888bd2b57fa
scope.13.id=function:board:get_mine
scope.13.kind=function
scope.13.startLine=85
scope.13.endLine=87
scope.13.semanticHash=7a62f802dd4ce5c2
scope.14.id=function:board:arm_mine
scope.14.kind=function
scope.14.startLine=89
scope.14.endLine=99
scope.14.semanticHash=21c3da9aac393cdb
scope.15.id=function:board:clear_mine
scope.15.kind=function
scope.15.startLine=101
scope.15.endLine=103
scope.15.semanticHash=4e98fb16b410a74c
scope.16.id=function:board:clear_all
scope.16.kind=function
scope.16.startLine=105
scope.16.endLine=108
scope.16.semanticHash=f43dc57d575b1c36
scope.17.id=function:_advance_one_step
scope.17.kind=function
scope.17.startLine=112
scope.17.endLine=121
scope.17.semanticHash=d3c45b12e42a84c3
scope.18.id=function:board:advance
scope.18.kind=function
scope.18.startLine=124
scope.18.endLine=139
scope.18.semanticHash=0014f4ccf8d457d7
scope.19.id=function:board:step_forward_by_facing
scope.19.kind=function
scope.19.startLine=143
scope.19.endLine=176
scope.19.semanticHash=9697389c81a0c72c
scope.20.id=function:board:step_backward_by_facing
scope.20.kind=function
scope.20.startLine=180
scope.20.endLine=201
scope.20.semanticHash=b26afe588205e91a
]]
