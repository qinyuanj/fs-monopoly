require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local board = require("src.rules.board.init")
local _config_reset = require("test.support.config_reset")

local _sorted_dirs_comparator = board._M_test._sorted_dirs_comparator
local _pick_any_dir = board._M_test._pick_any_dir

local function _assert_eq(a, b, msg)
  luassert.is.same(b, a, msg)
end

-- Board instance tests (mine and roadblock methods)

local function _make_board()
  local tiles = { { id = "T1", type = "land" }, { id = "T2", type = "start" } }
  local tile_lookup = {}
  for _, t in ipairs(tiles) do tile_lookup[t.id] = t end
  return board:new({
    path = tiles,
    tile_lookup = tile_lookup,
    branches = {},
    map = {},
    overlays = { roadblocks = {}, mines = {} },
  })
end



describe("TestBoardInit", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_comparator_up_before_right", function()
    _assert_eq(_sorted_dirs_comparator("up", "right"), true, "up < right")
  end)

  it("test_comparator_right_before_down", function()
    _assert_eq(_sorted_dirs_comparator("right", "down"), true, "right < down")
  end)

  it("test_comparator_down_before_left", function()
    _assert_eq(_sorted_dirs_comparator("down", "left"), true, "down < left")
  end)

  it("test_comparator_left_not_before_up", function()
    _assert_eq(_sorted_dirs_comparator("left", "up"), false, "left not < up")
  end)

  it("test_comparator_same_priority_uses_tostring", function()
    _assert_eq(_sorted_dirs_comparator("a", "b"), true, "a < b lexicographic")
    _assert_eq(_sorted_dirs_comparator("b", "a"), false, "b not < a lexicographic")
  end)

  it("test_comparator_same_key_returns_false", function()
    _assert_eq(_sorted_dirs_comparator("up", "up"), false, "same key not strictly less")
  end)

  it("test_comparator_unknown_before_known_when_alpha_lower", function()
    _assert_eq(_sorted_dirs_comparator("up", "alpha"), true, "up (priority 1) < alpha (priority 100)")
    _assert_eq(_sorted_dirs_comparator("alpha", "up"), false, "alpha not < up")
  end)

  it("test_pick_any_dir_returns_first_dir", function()
    local neigh = { up = 10, right = 20 }
    local dir, id = _pick_any_dir(neigh, nil)
    _assert_eq(dir, "up", "should pick 'up' first (priority 1)")
    _assert_eq(id, 10, "should return neighbor id for 'up'")
  end)

  it("test_pick_any_dir_avoids_specified_dir", function()
    local neigh = { up = 10, right = 20 }
    local dir, id = _pick_any_dir(neigh, "up")
    _assert_eq(dir, "right", "should pick 'right' when 'up' is avoided")
    _assert_eq(id, 20, "should return neighbor id for 'right'")
  end)

  it("test_pick_any_dir_returns_nil_if_only_avoid", function()
    local neigh = { up = 10 }
    local dir, id = _pick_any_dir(neigh, "up")
    _assert_eq(dir, nil, "should return nil dir when only option is avoided")
    _assert_eq(id, nil, "should return nil id when only option is avoided")
  end)

  it("test_pick_any_dir_single_dir_no_avoid", function()
    local neigh = { down = 5 }
    local dir, id = _pick_any_dir(neigh, nil)
    _assert_eq(dir, "down", "single dir returns that dir")
    _assert_eq(id, 5, "single dir returns correct id")
  end)

  it("test_pick_any_dir_prefers_priority_order", function()
    local neigh = { left = 40, right = 20, down = 30, up = 10 }
    local dir, _ = _pick_any_dir(neigh, nil)
    _assert_eq(dir, "up", "should pick 'up' (priority 1) over all others")
  end)

  it("test_pick_any_dir_nil_neigh_asserts", function()
    local ok, _ = pcall(_pick_any_dir, nil, nil)
    _assert_eq(ok, false, "should assert when neigh is nil")
  end)

  it("test_board_length", function()
    local b = _make_board()
    _assert_eq(b:length(), 2, "length should return path size")
  end)

  it("test_board_get_tile", function()
    local b = _make_board()
    local t = b:get_tile(1)
    _assert_eq(t.id, "T1", "get_tile(1) should return T1")
  end)

  it("test_board_index_of_tile_id", function()
    local b = _make_board()
    _assert_eq(b:index_of_tile_id("T2"), 2, "index_of_tile_id should return 2 for T2")
  end)

  it("test_board_get_tile_by_id", function()
    local b = _make_board()
    local t = b:get_tile_by_id("T1")
    _assert_eq(t.id, "T1", "get_tile_by_id should return T1")
  end)

  it("test_board_find_first_by_type", function()
    local b = _make_board()
    local idx, tile = b:find_first_by_type("start")
    _assert_eq(idx, 2, "find_first_by_type should return index 2 for start")
    _assert_eq(tile.id, "T2", "tile should be T2")
  end)

  it("test_board_find_first_by_type_not_found", function()
    local b = _make_board()
    local idx = b:find_first_by_type("hospital")
    _assert_eq(idx, nil, "find_first_by_type should return nil when not found")
  end)

  it("test_board_place_mine_nil_data", function()
    local b = _make_board()
    b:place_mine(1, nil)
    _assert_eq(b:has_mine(1), true, "has_mine should return true after placing mine with nil data")
    _assert_eq(b.overlays.mines[1], true, "mine stored as true when data is nil")
  end)

  it("test_board_place_mine_with_data", function()
    local b = _make_board()
    b:place_mine(1, { owner_id = 1001 })
    _assert_eq(b:has_mine(1), true, "has_mine should return true after placing mine with data")
    _assert_eq(b.overlays.mines[1].owner_id, 1001, "mine data should be stored")
  end)

  it("test_board_get_mine", function()
    local b = _make_board()
    b:place_mine(1, { armed = false })
    local mine = b:get_mine(1)
    _assert_eq(mine.armed, false, "get_mine should return mine data")
  end)

  it("test_board_clear_mine", function()
    local b = _make_board()
    b:place_mine(1, nil)
    b:clear_mine(1)
    _assert_eq(b:has_mine(1), false, "has_mine should return false after clear")
  end)

  it("test_board_roadblock_operations", function()
    local b = _make_board()
    _assert_eq(b:has_roadblock(1), false, "no roadblock initially")
    b:place_roadblock(1)
    _assert_eq(b:has_roadblock(1), true, "has_roadblock after place")
    b:clear_roadblock(1)
    _assert_eq(b:has_roadblock(1), false, "no roadblock after clear")
  end)

  it("test_board_get_overlays", function()
    local b = _make_board()
    local overlays = b:get_overlays()
    luassert.is_table(overlays, "get_overlays should return table")
  end)

  it("test_board_clear_all", function()
    local b = _make_board()
    b:place_roadblock(1)
    b:place_mine(1, nil)
    b:clear_all(1)
    _assert_eq(b:has_roadblock(1), false, "roadblock cleared")
    _assert_eq(b:has_mine(1), false, "mine cleared")
  end)

  it("test_board_advance_basic", function()
    local b = _make_board()
    local new_idx, passed = b:advance(1, 1, nil)
    _assert_eq(new_idx, 2, "advance 1 step from 1 should reach 2")
    _assert_eq(passed, 0, "should not pass start")
  end)

  it("test_board_advance_wraps", function()
    local b = _make_board()
    local new_idx, passed = b:advance(2, 1, nil)
    _assert_eq(new_idx, 1, "advance past end should wrap to 1")
    _assert_eq(passed, 1, "should have passed start once")
  end)


end)
