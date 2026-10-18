local target_layout = require("src.rules.board.target_layout")
local target_direction = require("src.rules.board.target_direction")

local board_query = {}

-- 行为测试公共接缝：test_board_query 观察队列扩展后的广度优先访问顺序。
function board_query.queue_walk(queue, visit)
  local pending = queue or {}
  local head = 1
  while head <= #pending do
    local node = pending[head]
    head = head + 1
    visit(node, function(next_node)
      pending[#pending + 1] = next_node
    end)
  end
end

local function _sort_by_distance_bucket(board, entries)
  table.sort(entries, function(left, right)
    local left_tile = board:get_tile(left)
    local right_tile = board:get_tile(right)
    if left_tile.id ~= right_tile.id then
      return left_tile.id < right_tile.id
    end
    return left < right
  end)
end

local function _push_into_bucket(by_dist, distance, idx)
  by_dist[distance] = by_dist[distance] or {}
  table.insert(by_dist[distance], idx)
end

-- 距离在 (0, max_dist] 内时返回距离,否则 nil。
local function _distance_within(start_tile, tile, max_dist)
  local distance = target_direction.manhattan_distance(start_tile, tile)
  if distance > 0 and distance <= max_dist then
    return distance
  end
  return nil
end

local function _sort_buckets(board, by_dist)
  for _, entries in pairs(by_dist) do
    _sort_by_distance_bucket(board, entries)
  end
end

local function _collect_indices_by_distance(board, start_tile, max_dist)
  local by_dist = {}
  for idx, tile in ipairs(board.path or {}) do
    if idx ~= board:index_of_tile_id(start_tile.id) then
      local distance = _distance_within(start_tile, tile, max_dist)
      if distance ~= nil then
        _push_into_bucket(by_dist, distance, idx)
      end
    end
  end
  _sort_buckets(board, by_dist)
  return by_dist
end

local function _flatten_by_distance(by_dist, max_dist)
  local list = {}
  for step = 1, max_dist do
    local entries = by_dist[step] or {}
    for _, idx in ipairs(entries) do
      table.insert(list, idx)
    end
  end
  return list
end

function board_query.indices_in_range(board, start, distance)
  assert(board ~= nil, "missing board")
  local start_tile = assert(board:get_tile(start), "missing start tile: " .. tostring(start))
  local max_dist = distance or 0
  if max_dist <= 0 then
    return {}
  end

  local by_dist = _collect_indices_by_distance(board, start_tile, max_dist)
  return _flatten_by_distance(by_dist, max_dist)
end

board_query.arrange_target_options = target_layout.arrange_target_options

return board_query

--[[ mutate4lua-manifest
version=4
projectHash=3fb8bea9650b3fe6
scope.0.id=chunk:src/rules/board/query.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=81
scope.0.semanticHash=6ddd054be7fc9c3d
scope.1.id=function:board_query.queue_walk
scope.1.kind=function
scope.1.startLine=6
scope.1.endLine=16
scope.1.semanticHash=e3ab035812cf91ac
scope.2.id=function:<anonymous>
scope.2.kind=function
scope.2.startLine=12
scope.2.endLine=14
scope.2.semanticHash=403f55c4187ffbe0
scope.3.id=function:_sort_by_distance_bucket
scope.3.kind=function
scope.3.startLine=18
scope.3.endLine=27
scope.3.semanticHash=fcf7da7e80de9003
scope.4.id=function:<anonymous>#2
scope.4.kind=function
scope.4.startLine=19
scope.4.endLine=26
scope.4.semanticHash=bc84497d4ec5d249
scope.5.id=function:_push_into_bucket
scope.5.kind=function
scope.5.startLine=29
scope.5.endLine=32
scope.5.semanticHash=a2536727ac854959
scope.6.id=function:_collect_indices_by_distance
scope.6.kind=function
scope.6.startLine=34
scope.6.endLine=48
scope.6.semanticHash=439a8f85c9c7a67f
scope.7.id=function:_flatten_by_distance
scope.7.kind=function
scope.7.startLine=50
scope.7.endLine=59
scope.7.semanticHash=57569e1892e3c2e9
scope.8.id=function:board_query.indices_in_range
scope.8.kind=function
scope.8.startLine=61
scope.8.endLine=71
scope.8.semanticHash=38eb6b67af3d6a43
]]
