require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local board_query = require("src.rules.board.query")
local support = require("test.support.shared_support")
local default_map = require("src.config.content.default_map")
local config_reset = require("test.support.config_reset")

local function linear_board(cols, index_of_override)
  local path = {}
  for index, col in ipairs(cols) do
    path[index] = { id = index, row = 0, col = col, type = "land" }
  end
  return {
    path = path,
    get_tile = function(_, index) return path[index] end,
    index_of_tile_id = index_of_override or function(_, id) return id end,
  }
end

local function walk(queue, expand, cap)
  local visited = {}
  board_query.queue_walk(queue, function(node, enqueue)
    assert(#visited < cap, "queue_walk repeated a node")
    visited[#visited + 1] = node
    if expand then expand(node, enqueue) end
  end)
  return visited
end

describe("TestBoardQuery", function()
  before_each(function() config_reset.reset_all() end)

  it("visits_a_single_node", function()
    luassert.same({ "a" }, walk({ "a" }, nil, 1))
  end)

  it("visits_no_nodes_in_an_empty_queue", function()
    luassert.same({}, walk({}, nil, 0))
  end)

  it("visits_no_nodes_in_a_nil_queue", function()
    luassert.same({}, walk(nil, nil, 0))
  end)

  it("enqueues_nodes_in_breadth_first_order", function()
    local visited = walk({ 1 }, function(node, enqueue)
      if node < 3 then enqueue(node + 1) end
    end, 3)
    luassert.same({ 1, 2, 3 }, visited)
  end)

  it("preserves_order_when_a_node_enqueues_multiple_children", function()
    local visited = walk({ 0 }, function(node, enqueue)
      if node == 0 then enqueue(1); enqueue(2) end
    end, 3)
    luassert.same({ 0, 1, 2 }, visited)
  end)

  it("visits_multiple_initial_nodes_in_order", function()
    luassert.same({ "x", "y", "z" }, walk({ "x", "y", "z" }, nil, 3))
  end)

  it("excludes_a_tile_co_located_with_the_start", function()
    luassert.same({ 3 }, board_query.indices_in_range(linear_board({ 0, 0, 1 }), 1, 5))
  end)

  it("excludes_the_index_reported_by_index_of_tile_id", function()
    local board = linear_board({ 0, 5 }, function(_, id)
      if id == 1 then return 2 end
      return id
    end)
    luassert.same({}, board_query.indices_in_range(board, 1, 10))
  end)

  it("returns_no_candidates_for_nil_distance", function()
    luassert.same({}, board_query.indices_in_range(linear_board({ 0, 1 }), 1, nil))
  end)

  it("returns_no_candidates_for_zero_distance", function()
    luassert.same({}, board_query.indices_in_range(linear_board({ 0, 1 }), 1, 0))
  end)

  it("includes_the_adjacent_tile_at_distance_one", function()
    luassert.same({ 2 }, board_query.indices_in_range(linear_board({ 0, 1, 2 }), 1, 1))
  end)

  it("orders_tiles_by_distance_and_skips_missing_distances", function()
    luassert.same({ 3, 4, 2 }, board_query.indices_in_range(linear_board({ 0, 3, 1, 1 }), 1, 5))
  end)

  it("includes_tiles_at_the_manhattan_radius_boundary", function()
    local game = support.new_game({ map = default_map })
    local start = game.board:index_of_tile_id(1)
    local target = game.board:index_of_tile_id(34)
    luassert.is_true(support.list_contains(board_query.indices_in_range(game.board, start, 4), target))
    luassert.is_false(support.list_contains(board_query.indices_in_range(game.board, start, 2), target))
  end)

  it("rejects_a_missing_board", function()
    local ok, err = pcall(board_query.indices_in_range, nil, 1, 5)
    luassert.is_false(ok)
    luassert.truthy(tostring(err):find("missing board", 1, true))
  end)
end)
