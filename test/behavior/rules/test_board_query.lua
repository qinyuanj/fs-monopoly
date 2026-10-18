require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local board_query = require("src.rules.board.query")
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local _config_reset = require("test.support.config_reset")

local function _new_game()
  return support.new_game({ map = default_map })
end

local function _assert_eq(a, b, msg)
  luassert.is.same(b, a, msg)
end



-- L11 `head = head + 1` 的 `+ -> -` 变异体让 head 回头、`1 -> 0` 让 head 恒为 1
-- 原地踏步:两者都是无限循环(队列永不动)。死循环杀法不是断言——断言永远到不了,
-- 而是给 visit 挂「访问次数上限」守卫:变异体重复访问同一节点超上限即报错,
-- 测试快速失败,fail_fast 中止;基线每个节点恰好访问一次,守卫不触发。
local function _capped_visit(visited, cap, node)
  if #visited >= cap then
    error("queue_walk must visit each node at most once (cap " .. tostring(cap) .. ")")
  end
  visited[#visited + 1] = node
end

describe("TestBoardQueryCrapCoverage", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_queue_walk_visits_single_node", function()
    local visited = {}
    board_query.queue_walk({ "a" }, function(node, _enqueue)
      _capped_visit(visited, 1, node)
    end)
    _assert_eq(#visited, 1, "single node: visited once")
    _assert_eq(visited[1], "a", "single node: correct value")
  end)

  it("test_queue_walk_visits_empty_queue", function()
    local visited = {}
    board_query.queue_walk({}, function(node, _enqueue)
      _capped_visit(visited, 0, node)
    end)
    _assert_eq(#visited, 0, "empty queue: nothing visited")
  end)

  it("test_queue_walk_visits_nil_queue", function()
    local visited = {}
    board_query.queue_walk(nil, function(node, _enqueue)
      _capped_visit(visited, 0, node)
    end)
    _assert_eq(#visited, 0, "nil queue: nothing visited")
  end)

  it("test_queue_walk_enqueue_expands_breadth_first", function()
    local visited = {}
    board_query.queue_walk({ 1 }, function(node, enqueue)
      _capped_visit(visited, 3, node)
      if node < 3 then
        enqueue(node + 1)
      end
    end)
    _assert_eq(#visited, 3, "bfs: visits 3 nodes")
    _assert_eq(visited[1], 1, "bfs: first node is 1")
    _assert_eq(visited[2], 2, "bfs: second node is 2")
    _assert_eq(visited[3], 3, "bfs: third node is 3")
  end)

  it("test_queue_walk_multiple_enqueue_per_node", function()
    local visited = {}
    board_query.queue_walk({ 0 }, function(node, enqueue)
      _capped_visit(visited, 3, node)
      if node == 0 then
        enqueue(1)
        enqueue(2)
      end
    end)
    _assert_eq(#visited, 3, "multi-enqueue: all enqueued nodes visited")
    _assert_eq(visited[1], 0, "multi-enqueue: root visited first")
    _assert_eq(visited[2], 1, "multi-enqueue: first enqueued second")
    _assert_eq(visited[3], 2, "multi-enqueue: second enqueued third")
  end)

  it("test_queue_walk_visits_multiple_initial_nodes", function()
    local visited = {}
    board_query.queue_walk({ "x", "y", "z" }, function(node, _enqueue)
      _capped_visit(visited, 3, node)
    end)
    _assert_eq(#visited, 3, "multi-initial: all 3 initial nodes visited")
    _assert_eq(visited[1], "x", "multi-initial: x first")
    _assert_eq(visited[2], "y", "multi-initial: y second")
    _assert_eq(visited[3], "z", "multi-initial: z third")
  end)

-- Linear boards used to pin range boundaries. Tiles sit on row 0 with distinct
-- columns, so manhattan distance between indices i and j is |col_i - col_j|.
-- index_of_tile_id defaults to identity but can be overridden to model boards
-- whose id->index lookup differs from path order.
end)
local function _linear_board(cols, index_of_override)
  local path = {}
  for i, col in ipairs(cols) do
    path[i] = { id = i, row = 0, col = col, type = "land" }
  end
  return {
    path = path,
    get_tile = function(_, idx) return path[idx] end,
    index_of_tile_id = index_of_override or function(_, id) return id end,
  }
end

local function _sorted_copy(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  table.sort(out)
  return out
end



describe("TestBoardQueryIndicesInRangeBoundaries", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_excludes_a_tile_co_located_with_the_start", function()
    -- Index 2 shares the start's position (distance 0). The strict distance > 0
    -- guard must drop it even though it is within range.
    local board = _linear_board({ 0, 0, 1 })
    local result = board_query.indices_in_range(board, 1, 5)
    _assert_eq(#result, 1, "co-located tile excluded: only the distance-1 tile remains")
    _assert_eq(result[1], 3, "co-located tile excluded: index 3 is the sole in-range tile")
  end)

  it("test_collect_never_buckets_a_co_located_tile_at_distance_zero", function()
    -- L37 `distance > 0` -> `>=`:变异体把 distance=0 的并列格放进 by_dist[0]
    -- 桶;flatten 只走 1..max,桶 0 永不上浮,公共入口测不出,必须直测
    -- _collect_indices_by_distance 的分桶面。
    local board = _linear_board({ 0, 0, 1 })
    local by_dist = board_query._collect_indices_by_distance(board, board:get_tile(1), 5)
    luassert.truthy(by_dist[0] == nil, "distance-0 co-located tile must not enter any bucket")
    _assert_eq(#by_dist[1], 1, "distance-1 bucket holds the sole in-range tile")
  end)

  it("test_excludes_the_index_reported_by_index_of_tile_id", function()
    -- The board's id->index lookup maps the start's id to index 2 (a far tile),
    -- so the self-exclusion guard must skip index 2, leaving no in-range tiles.
    local board = _linear_board({ 0, 5 }, function(_, id)
      if id == 1 then return 2 end
      return id
    end)
    local result = board_query.indices_in_range(board, 1, 10)
    _assert_eq(#result, 0, "index_of_tile_id exclusion: the reported index is dropped")
  end)

  it("test_flatten_ignores_a_distance_zero_bucket", function()
    -- _flatten walks step 1..max, so a bucket keyed at 0 must never surface.
    local result = board_query._flatten_by_distance({ [0] = { 99 }, [1] = { 7 } }, 1)
    _assert_eq(#result, 1, "distance-0 bucket ignored: single flattened entry")
    _assert_eq(result[1], 7, "distance-0 bucket ignored: only the distance-1 index remains")
  end)

  it("test_nil_distance_yields_no_candidates", function()
    -- distance defaults to 0, and max_dist <= 0 short-circuits to an empty list.
    local board = _linear_board({ 0, 1 })
    local result = board_query.indices_in_range(board, 1, nil)
    _assert_eq(#result, 0, "nil distance: no candidates in range")
  end)

  it("test_distance_one_includes_the_adjacent_tile", function()
    -- max_dist == 1 must still pass the <= 0 gate and collect the distance-1 tile.
    local board = _linear_board({ 0, 1, 2 })
    local result = _sorted_copy(board_query.indices_in_range(board, 1, 1))
    _assert_eq(#result, 1, "distance 1: exactly the adjacent tile")
    _assert_eq(result[1], 2, "distance 1: index 2 is the adjacent tile")
  end)

-- Characterization tests for the manhattan bucketing helpers behind
-- indices_in_range. Previously duplicated as inlined copies inside movement_spec.
end)


describe("TestBoardQueryManhattanBucketingHelpers", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_collect_indices_by_distance_returns_empty_for_zero_distance", function()
    local g = _new_game()
    local start_tile = g.board:get_tile(1)
    local by_dist = board_query._collect_indices_by_distance(g.board, start_tile, 0)
    luassert.is_table(by_dist, "should return a table")
    luassert.is_nil(next(by_dist), "should return empty table for max_dist=0")
  end)

  it("test_collect_indices_by_distance_groups_tiles_by_manhattan_radius", function()
    local g = _new_game()
    local start_idx = g.board:index_of_tile_id(1)
    local start_tile = g.board:get_tile(start_idx)
    local by_dist = board_query._collect_indices_by_distance(g.board, start_tile, 4)
    local target_idx = g.board:index_of_tile_id(34)
    luassert.is_not_nil(by_dist[4], "should have entries at distance 4")
    luassert.truthy(support.list_contains(by_dist[4], target_idx), "should group tiles by manhattan radius")
  end)

  it("test_collect_indices_by_distance_does_not_exceed_max_dist", function()
    local g = _new_game()
    local start_idx = g.board:index_of_tile_id(1)
    local start_tile = g.board:get_tile(start_idx)
    local by_dist = board_query._collect_indices_by_distance(g.board, start_tile, 2)
    luassert.is_nil(by_dist[3], "should not have entries beyond max_dist")
    luassert.is_nil(by_dist[4], "should not have entries beyond max_dist")
  end)

  it("test_manhattan_distance_uses_tile_coordinates", function()
    local distance = board_query._manhattan_distance({ row = 9, col = 8 }, { row = 5, col = 8 })
    _assert_eq(distance, 4, "manhattan distance should use absolute row/col deltas")
  end)

  it("test_flatten_by_distance_returns_empty_for_empty_input", function()
    local result = board_query._flatten_by_distance({}, 3)
    luassert.is_table(result, "should return a table")
    luassert.is.same(0, #result, "should return empty list for empty input")
  end)

  it("test_flatten_by_distance_orders_by_distance", function()
    local by_dist = {
      [1] = { 10, 11 },
      [2] = { 20, 21 },
      [3] = { 30 },
    }
    local result = board_query._flatten_by_distance(by_dist, 3)
    _assert_eq(#result, 5, "should return all entries")
    _assert_eq(result[1], 10, "first entry should be from distance 1")
    _assert_eq(result[2], 11, "second entry should be from distance 1")
    _assert_eq(result[3], 20, "third entry should be from distance 2")
    _assert_eq(result[4], 21, "fourth entry should be from distance 2")
    _assert_eq(result[5], 30, "fifth entry should be from distance 3")
  end)

  it("test_flatten_by_distance_skips_missing_distances", function()
    local by_dist = {
      [1] = { 10 },
      [3] = { 30 },
    }
    local result = board_query._flatten_by_distance(by_dist, 3)
    _assert_eq(#result, 2, "should return only existing entries")
    _assert_eq(result[1], 10, "first entry should be from distance 1")
    _assert_eq(result[2], 30, "second entry should be from distance 3")
  end)

  it("test_flatten_by_distance_handles_max_dist_greater_than_entries", function()
    local by_dist = {
      [1] = { 10 },
    }
    local result = board_query._flatten_by_distance(by_dist, 5)
    _assert_eq(#result, 1, "should return only existing entries even when max_dist is larger")
  end)
end)
describe("TestBoardQueryIndicesInRangeBoundaries", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_asserts_missing_board_with_message", function()
    -- #293:indices_in_range 的 missing board 断言消息未测。
    local ok, err = pcall(board_query.indices_in_range, nil, 1, 5)
    luassert.truthy(ok == false, "indices_in_range without board should assert")
    luassert.truthy(tostring(err):find("missing board", 1, true) ~= nil, "assert should carry its message: " .. tostring(err))
  end)

end)
