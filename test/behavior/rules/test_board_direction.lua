require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local board = require("src.rules.board.init")
local direction = require("src.rules.board.direction")
local _config_reset = require("test.support.config_reset")

local _resolve_outer_next = board._M_test._resolve_outer_next
local _resolve_fresh_forward_next = board._M_test._resolve_fresh_forward_next
local _resolve_facing_next = board._M_test._resolve_facing_next
local _resolve_fallback_next = board._M_test._resolve_fallback_next
local _resolve_backward_from_neighbors = board._M_test._resolve_backward_from_neighbors
local _resolve_backward_next_source = direction.resolve_backward_next_source
local function _resolve_backward_next_id(map, current_id, neigh, facing)
  return _resolve_backward_next_source(map, current_id, neigh, facing).next_id
end

local opposite = { up = "down", down = "up", left = "right", right = "left" }

local function _assert_eq(a, b, msg)
  luassert.is.same(b, a, msg)
end



describe("TestBoardDirectionCrapCoverage", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_resolve_fallback_next_unique_forward", function()
    local neigh = { up = 1, down = 2 }
    local facing = "up"
    local next_id = _resolve_fallback_next(neigh, facing)
    _assert_eq(opposite[facing], "down", "resolve_fallback opposite check")
    _assert_eq(next_id, 1, "resolve_fallback unique non-back should return forward id")
  end)

  it("test_resolve_fallback_next_multiple_forward_falls_to_pick_any", function()
    local neigh = { up = 1, right = 2, down = 3 }
    local next_id = _resolve_fallback_next(neigh, "up")
    _assert_eq(next_id, 1, "resolve_fallback multiple non-back should pick up by priority")
  end)

  it("test_resolve_fallback_next_last_resort_any_dir", function()
    local neigh = { down = 3 }
    local next_id = _resolve_fallback_next(neigh, "up")
    _assert_eq(next_id, 3, "resolve_fallback only back dir should return it as last resort")
  end)

  it("test_resolve_fallback_next_no_neighbors_returns_nil", function()
    local neigh = {}
    local next_id = _resolve_fallback_next(neigh, "up")
    _assert_eq(next_id, nil, "resolve_fallback empty neighbors should return nil")
  end)

  it("test_resolve_backward_from_neighbors_unique_backward", function()
    local neigh = { up = 1, down = 2 }
    local next_id = _resolve_backward_from_neighbors(neigh, "up")
    _assert_eq(next_id, 2, "resolve_backward unique non-facing should return down id")
  end)

  it("test_resolve_backward_from_neighbors_multiple_non_facing_falls_to_pick_any", function()
    local neigh = { up = 1, right = 2, down = 3 }
    local next_id = _resolve_backward_from_neighbors(neigh, "up")
    _assert_eq(next_id, 2, "resolve_backward multiple non-facing should pick right by priority")
  end)

  it("test_resolve_backward_from_neighbors_only_facing_last_resort", function()
    local neigh = { up = 3 }
    local next_id = _resolve_backward_from_neighbors(neigh, "up")
    _assert_eq(next_id, 3, "resolve_backward only facing should return it as last resort")
  end)

  it("test_resolve_backward_from_neighbors_no_neighbors_returns_nil", function()
    local neigh = {}
    local next_id = _resolve_backward_from_neighbors(neigh, "up")
    _assert_eq(next_id, nil, "resolve_backward empty neighbors should return nil")
  end)

-- Characterization tests for the forward/backward next-id resolver helpers.
-- These pin the branch order the production movement path depends on; they were
-- previously duplicated as inlined copies inside movement_spec.
end)


describe("TestBoardDirectionResolverCharacterization", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_resolve_outer_next_returns_outer_next_when_no_entry", function()
    local map = {
      outer_next = { [1] = 2 },
      entry_points = {},
      outer_prev = {},
      direction = function() return "up" end,
    }
    local result = _resolve_outer_next(map, 1, { parity = "up", entered_inner = false, skip_entry_on_tile_id = nil })
    _assert_eq(result, 2, "should return outer_next when no entry point")
  end)

  it("test_resolve_outer_next_returns_inner_on_even_parity", function()
    local map = {
      outer_next = { [1] = 2 },
      entry_points = { [1] = { inner_id = 10 } },
      outer_prev = { [1] = 99 },
    }
    local result, entered_inner = _resolve_outer_next(map, 1, { parity = 2, entered_inner = false, skip_entry_on_tile_id = nil })
    _assert_eq(result, 10, "should return inner_id on even parity")
    _assert_eq(entered_inner, true, "should mark inner entry on even parity")
  end)

  it("test_resolve_outer_next_returns_outer_when_inner_entry_is_blocked", function()
    local map = {
      outer_next = { [1] = 2 },
      entry_points = { [1] = { inner_id = 10 } },
      outer_prev = { [1] = 99 },
    }
    local result, entered_inner = _resolve_outer_next(map, 1, { parity = 2, entered_inner = true, skip_entry_on_tile_id = nil })
    _assert_eq(result, 2, "should return outer_next when same move already entered inner")
    _assert_eq(entered_inner, false, "should not mark inner entry when blocked")
  end)

  it("test_resolve_outer_next_returns_nil_when_no_outer_next", function()
    local map = {
      outer_next = {},
      entry_points = {},
      outer_prev = {},
    }
    local result, entered_inner = _resolve_outer_next(map, 1, { parity = 1, entered_inner = false, skip_entry_on_tile_id = nil })
    _assert_eq(result, nil, "should return nil when no outer_next")
    _assert_eq(entered_inner, false, "should not mark inner entry when outer_next is missing")
  end)

  it("test_resolve_fresh_forward_next_returns_fresh_next_when_facing_nil", function()
    local map = {
      fresh_forward_next = { [1] = 5 },
    }
    local result = _resolve_fresh_forward_next(map, 1, nil)
    _assert_eq(result, 5, "should return fresh_forward_next when facing is nil")
  end)

  it("test_resolve_fresh_forward_next_returns_nil_when_facing_not_nil", function()
    local map = {
      fresh_forward_next = { [1] = 5 },
    }
    local result = _resolve_fresh_forward_next(map, 1, "up")
    _assert_eq(result, nil, "should return nil when facing is not nil")
  end)

  it("test_resolve_fresh_forward_next_returns_nil_when_no_fresh_forward_next", function()
    local map = {}
    local result = _resolve_fresh_forward_next(map, 1, nil)
    _assert_eq(result, nil, "should return nil when no fresh_forward_next")
  end)

  it("test_resolve_facing_next_returns_neighbor_in_facing_direction", function()
    local neigh = { up = 10, down = 20, left = 30, right = 40 }
    local result = _resolve_facing_next(neigh, "up")
    _assert_eq(result, 10, "should return neighbor in facing direction")
  end)

  it("test_resolve_facing_next_returns_nil_when_no_facing", function()
    local neigh = { up = 10 }
    local result = _resolve_facing_next(neigh, nil)
    _assert_eq(result, nil, "should return nil when facing is nil")
  end)

  it("test_resolve_facing_next_returns_nil_when_no_neighbor_in_facing", function()
    local neigh = { up = 10 }
    local result = _resolve_facing_next(neigh, "down")
    _assert_eq(result, nil, "should return nil when no neighbor in facing direction")
  end)

  it("test_resolve_fallback_next_returns_unique_dir_avoiding_back", function()
    -- When facing="up", back_dir="down" (opposite)
    -- neigh has "up" and "down", avoiding "down" leaves only "up"
    local neigh = { up = 10, down = 20 }
    local result = _resolve_fallback_next(neigh, "up")
    _assert_eq(result, 10, "should return unique dir avoiding back direction (down)")
  end)

  it("test_resolve_fallback_next_returns_any_dir_avoiding_back_when_not_unique", function()
    -- When facing="up", back_dir="down"
    -- neigh has up=10, down=20, left=30 - avoiding "down" leaves "up" and "left"
    -- 多候选时 unique 语义不成立,回落链走 any-dir 优先级取向
    -- Then _pick_any_dir is called which returns the first sorted dir (left before up)
    local neigh = { up = 10, down = 20, left = 30 }
    local result = _resolve_fallback_next(neigh, "up")
    luassert.is_not_nil(result, "should return some direction when multiple options")
    luassert.is_not.same(20, result, "should not return back direction (down)")
  end)

  it("test_resolve_fallback_next_returns_any_dir_when_back_nil", function()
    local neigh = { up = 10 }
    local result = _resolve_fallback_next(neigh, nil)
    _assert_eq(result, 10, "should return any dir when back direction is nil")
  end)

  it("test_resolve_backward_next_returns_facing_reverse_neighbor_when_available", function()
    local map = {
      outer_prev = { [1] = 30 },
      backward_fallback = { [1] = 40 },
    }
    local neigh = { down = 20, left = 50 }
    local result = _resolve_backward_next_id(map, 1, neigh, "up")
    _assert_eq(result, 20, "should prefer the reverse-facing neighbor before all other backward sources")
  end)

  it("test_resolve_backward_next_returns_outer_prev_before_map_fallback", function()
    local map = {
      outer_prev = { [1] = 30 },
      backward_fallback = { [1] = 40 },
    }
    local neigh = { left = 50 }
    local result = _resolve_backward_next_id(map, 1, neigh, nil)
    _assert_eq(result, 30, "should prefer outer_prev before backward_fallback")
  end)

  it("test_resolve_backward_next_returns_backward_fallback_before_neighbor_fallback", function()
    local map = {
      outer_prev = {},
      backward_fallback = { [1] = 40 },
    }
    local neigh = { left = 50, right = 60 }
    local result = _resolve_backward_next_id(map, 1, neigh, nil)
    _assert_eq(result, 40, "should prefer backward_fallback before neighbor fallback")
  end)

  it("test_resolve_backward_next_returns_unique_neighbor_when_only_one_remains", function()
    local map = {
      outer_prev = {},
      backward_fallback = {},
    }
    local neigh = { up = 10, left = 20 }
    local result = _resolve_backward_next_id(map, 1, neigh, "up")
    _assert_eq(result, 20, "should return the unique remaining neighbor when one option remains")
  end)

  it("test_resolve_backward_next_returns_sorted_any_neighbor_when_multiple_remain", function()
    local map = {
      outer_prev = {},
      backward_fallback = {},
    }
    local neigh = { up = 10, right = 30, left = 20 }
    local result = _resolve_backward_next_id(map, 1, neigh, "up")
    _assert_eq(result, 30, "should fall back to the first sorted non-facing neighbor when multiple options remain")
  end)

  it("test_resolve_backward_next_source_reports_facing_hit", function()
    local map = {
      outer_prev = {},
      backward_fallback = {},
    }
    local neigh = { down = 20, left = 50 }
    local result = _resolve_backward_next_source(map, 1, neigh, "up")
    _assert_eq(result.next_id, 20, "result should keep the reverse-facing neighbor")
    _assert_eq(result.source, "facing_reverse_neighbor", "result should report facing hit as the source")
  end)

  it("test_resolve_backward_next_source_reports_outer_prev_hit", function()
    local map = {
      outer_prev = { [1] = 30 },
      backward_fallback = { [1] = 40 },
    }
    local neigh = { left = 50 }
    local result = _resolve_backward_next_source(map, 1, neigh, nil)
    _assert_eq(result.next_id, 30, "result should keep the outer_prev tile")
    _assert_eq(result.source, "outer_prev", "result should report outer_prev as the source")
  end)

  it("test_resolve_backward_next_source_reports_backward_fallback_hit", function()
    local map = {
      outer_prev = {},
      backward_fallback = { [1] = 40 },
    }
    local neigh = { left = 50, right = 60 }
    local result = _resolve_backward_next_source(map, 1, neigh, nil)
    _assert_eq(result.next_id, 40, "result should keep the backward fallback tile")
    _assert_eq(result.source, "backward_fallback", "result should report backward_fallback as the source")
  end)

end)
