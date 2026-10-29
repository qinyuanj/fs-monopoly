-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local function _assert_eq(actual, expected, message) luassert.is.equal(expected, actual, message) end
local _with_patches = support.with_patches

local contiguous_count = require("src.ui.view.contiguous_count")
local visual_sync = require("src.ui.render.board.visual_sync")

if not math.Vector3 then
  function math.Vector3(x, y, z)
    return { x = x, y = y, z = z }
  end
end

local function _build_board(tiles, neighbors)
  local lookup = {}
  local index_by_id = {}
  for index, tile in ipairs(tiles) do
    lookup[tile.id] = tile
    index_by_id[tile.id] = index
  end
  local board = {
    path = tiles,
    tile_lookup = lookup,
    map = { neighbors = neighbors or {} },
  }
  function board:get_tile_by_id(tile_id)
    return lookup[tile_id]
  end
  function board:index_of_tile_id(tile_id)
    return index_by_id[tile_id]
  end
  return board
end

describe("TestContiguousVisualSync", function()

  it("test_contiguous_count_ignores_non_land_neighbors_when_building_owner_components", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10 },
      { id = 39, type = "market", owner_id = 10 },
      { id = 2, type = "land", owner_id = 10 },
    }, {
      [1] = { right = 39 },
      [39] = { left = 1, right = 2 },
      [2] = { left = 39 },
    })

    local counts = contiguous_count.build_for_owner(board, 10)

    _assert_eq(contiguous_count.for_tile(board, 1, 10), 1, "non-land neighbor should not connect land tiles")
    _assert_eq(counts[1], 1, "first isolated land tile should count itself")
    _assert_eq(counts[2], 1, "second isolated land tile should count itself")
    _assert_eq(counts[39], nil, "non-land tile should not receive a contiguous count")
  end)

  it("test_contiguous_count_counts_each_tile_once_when_the_land_component_contains_a_cycle", function()
    -- 真实棋盘是网格,连片地块之间必然成环:地块 3 同时是 2 和 4 的邻居。
    -- BFS 的 visited 标记必须真的挡住重复入队,否则 3 会被数两次。
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10 },
      { id = 2, type = "land", owner_id = 10 },
      { id = 3, type = "land", owner_id = 10 },
      { id = 4, type = "land", owner_id = 10 },
    }, {
      [1] = { right = 2, left = 4 },
      [2] = { left = 1, right = 3 },
      [3] = { left = 2, right = 4 },
      [4] = { left = 3, right = 1 },
    })

    _assert_eq(contiguous_count.for_tile(board, 1, 10), 4, "a 4-cycle of owned land should count exactly four tiles")

    local counts = contiguous_count.build_for_owner(board, 10)
    _assert_eq(counts[1], 4, "every tile in the cycle shares the component size")
    _assert_eq(counts[3], 4, "the tile reachable from two neighbours must not be double counted")
  end)

  it("test_contiguous_count_falls_back_to_the_get_tile_by_id_seam_when_no_tile_lookup_exists", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10 },
      { id = 2, type = "land", owner_id = 10 },
      { id = 3, type = "land", owner_id = 20 },
    }, {
      [1] = { right = 2 },
      [2] = { left = 1, right = 3 },
      [3] = { left = 2 },
    })
    board.tile_lookup = nil -- force _owner_of through the function seam

    _assert_eq(contiguous_count.for_tile(board, 1, 10), 2, "connected owner land tiles should count via get_tile_by_id")
    _assert_eq(contiguous_count.for_tile(board, 3, 20), 1, "isolated owner tile should count itself via the seam")
  end)

  it("test_contiguous_count_returns_zero_for_nil_inputs_and_owner_mismatches", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10 },
    }, { [1] = {} })

    _assert_eq(contiguous_count.for_tile(nil, 1, 10), 0, "nil board should yield zero")
    _assert_eq(contiguous_count.for_tile(board, nil, 10), 0, "nil tile id should yield zero")
    _assert_eq(contiguous_count.for_tile(board, 1, nil), 0, "nil owner id should yield zero")
    _assert_eq(contiguous_count.for_tile(board, 1, 99), 0, "owner mismatch should yield zero")
    _assert_eq(next(contiguous_count.build_for_owner(nil, 10)), nil, "nil board should produce no owner counts")
    _assert_eq(next(contiguous_count.build_for_owner(board, nil)), nil, "nil owner id should produce no counts")
  end)

  it("test_contiguous_count_treats_a_board_without_a_neighbour_map_as_fully_disconnected", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10 },
      { id = 2, type = "land", owner_id = 10 },
    })
    board.map = nil -- no neighbour map: land tiles cannot connect

    _assert_eq(contiguous_count.for_tile(board, 1, 10), 1, "without a neighbour map each owned tile counts only itself")
    local counts = contiguous_count.build_for_owner(board, 10)
    _assert_eq(counts[1], 1, "first tile is its own singleton component")
    _assert_eq(counts[2], 1, "second tile is its own singleton component")
  end)

  it("test_contiguous_count_can_project_the_same_component_rent_total_to_each_owned_tile", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10, level = 1, price = 100, upgrade_costs = { 100 } },
      { id = 2, type = "land", owner_id = 10, level = 0, price = 100 },
      { id = 3, type = "land", owner_id = 20, level = 0, price = 100 },
    }, {
      [1] = { right = 2 },
      [2] = { left = 1, right = 3 },
      [3] = { left = 2 },
    })

    local rents = contiguous_count.build_rent_for_owner(board, 10, function(tile)
      if tile.level == 1 then return 100 end
      return 50
    end)

    _assert_eq(rents[1], 150, "first connected owner tile should receive component total rent")
    _assert_eq(rents[2], 150, "second connected owner tile should receive the same component total rent")
    _assert_eq(rents[3], nil, "other owner tile should not receive this owner's rent total")
  end)

  it("test_contiguous_count_yields_zero_when_neither_read_seam_can_resolve_an_owner", function()
    local board = { path = {}, map = { neighbors = {} } } -- no tile_lookup, no get_tile_by_id

    _assert_eq(contiguous_count.for_tile(board, 1, 10), 0, "unresolvable owner should yield zero")
    _assert_eq(next(contiguous_count.build_for_owner(board, 10)), nil, "empty board should produce no counts")
  end)

  it("test_build_rent_for_owner_returns_an_empty_map_for_a_non_function_rent_callback", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10 },
      { id = 2, type = "land", owner_id = 10 },
    }, {
      [1] = { right = 2 },
      [2] = { left = 1 },
    })
    _assert_eq(next(contiguous_count.build_rent_for_owner(board, 10, nil)), nil,
      "a non-function rent callback should short-circuit to an empty rent map")
  end)

  it("test_visual_sync_expands_affected_owners_dedupes_explicit_tiles_and_renders_contiguous_rent_totals", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10, level = 1, price = 100, upgrade_costs = { 100 } },
      { id = 2, type = "land", owner_id = 10, level = 0, price = 100 },
      { id = 3, type = "land", owner_id = 20, level = 0, price = 100 },
    }, {
      [1] = { right = 2 },
      [2] = { left = 1, right = 3 },
      [3] = { left = 2 },
    })
    local game = {
      board = board,
      turn = {},
    }
    function game:find_player_by_id(player_id)
      if player_id == 10 then
        return { id = 10, name = "Ada" }
      end
      return nil
    end
    local state = {
      game = game,
      board_scene = {
        tiles = {
          [1] = { name = "unit_1" },
          [2] = { name = "unit_2" },
          [3] = { name = "unit_3" },
        },
      },
    }
    local calls = {}

    _with_patches({
      {
        target = require("src.ui.render.board.tile"),
        key = "render_tile",
        value = function(unit, tile_id, owner_id, owner_name, level, contiguous_rent)
          calls[#calls + 1] = {
            unit = unit,
            tile_id = tile_id,
            owner_id = owner_id,
            owner_name = owner_name,
            level = level,
            contiguous_rent = contiguous_rent,
          }
        end,
      },
    }, function()
      local handled = visual_sync.sync_many(state, {
        tile_ids = { 1, 1 },
        affected_owner_ids = { 10, 10 },
      })
      _assert_eq(handled, true, "sync_many should handle rendered owner tiles")
    end)

    _assert_eq(#calls, 2, "explicit and expanded owner tiles should be rendered once each")
    _assert_eq(calls[1].tile_id, 1, "explicit tile should render first")
    _assert_eq(calls[1].owner_name, "Ada", "owner name should be resolved for renderer")
    _assert_eq(calls[1].level, 1, "tile level should be forwarded")
    _assert_eq(calls[1].contiguous_rent, 150, "first connected owner tile should receive total contiguous rent")
    _assert_eq(calls[2].tile_id, 2, "affected owner expansion should render second owned tile")
    _assert_eq(calls[2].contiguous_rent, 150, "second connected owner tile should receive total contiguous rent")
  end)

  it("test_visual_sync_uses_building_branch_when_scene_exposes_building_groups", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10, level = 2 },
    })
    local state = {
      game = { board = board },
      board_scene = {
        tiles = { [1] = { name = "unit_1" } },
        buildings = { [1] = {} },
        building_unit_groups = {},
      },
    }
    local spawned = nil

    _with_patches({
      {
        target = require("src.ui.render.board.tile"),
        key = "render_tile",
        value = function() end,
      },
      {
        target = require("src.ui.render.board.building_effects"),
        key = "spawn_upgrade_building_units",
        value = function(scene, _q, idx, level)
          spawned = { scene = scene, idx = idx, level = level }
          return true
        end,
      },
    }, function()
      local handled = visual_sync.sync_tile_visual(state, 1)
      _assert_eq(handled, true, "building branch should mark tile sync handled")
    end)

    _assert_eq(spawned.scene, state.board_scene, "building sync should use board scene")
    _assert_eq(spawned.idx, 1, "building sync should use board index")
    _assert_eq(spawned.level, 2, "building sync should forward tile level")
  end)

  it("test_visual_sync_keeps_overlay_while_matching_trigger_animation_is_queued", function()
    local board = {
      has_roadblock = function(_, idx)
        _assert_eq(idx, 1, "roadblock check should receive board index")
        return false
      end,
      has_mine = function(_, idx)
        _assert_eq(idx, 1, "mine check should receive board index")
        return false
      end,
    }
    local state = {
      game = {
        board = board,
        turn = {
          action_anim_queue = {
            { kind = "roadblock_trigger", tile_index = 1 },
          },
        },
      },
      board_scene = {},
    }
    local cleared = {}

    _with_patches({
      {
        target = require("src.ui.render.anim.overlay_runtime"),
        key = "clear_overlay",
        value = function(_, kind, idx)
          cleared[#cleared + 1] = kind .. ":" .. tostring(idx)
        end,
      },
    }, function()
      local handled = visual_sync.sync_overlay_visual(state, 1)
      _assert_eq(handled, true, "overlay sync should handle valid board index")
    end)

    _assert_eq(#cleared, 1, "queued roadblock trigger should suppress roadblock clear only")
    _assert_eq(cleared[1], "mine:1", "mine overlay should still clear without matching pending animation")
  end)

  it("test_sync_many_keeps_overlay_when_state_clear_arrives_with_a_pending_trigger", function()
    -- #550 缝:rules 同拍「先入队 trigger、后清 board 状态」→ sync_many 到达时
    -- has_roadblock 已为 false,但 pending 守卫查到队列内 trigger,overlay 必须保留。
    local board = {
      has_roadblock = function() return false end, -- 状态同拍已清
      has_mine = function() return false end,
    }
    local state = {
      game = {
        board = board,
        turn = {
          action_anim_queue = {
            { kind = "roadblock_trigger", tile_index = 1 },
          },
        },
      },
      board_scene = {},
    }
    local cleared = {}

    _with_patches({
      {
        target = require("src.ui.render.anim.overlay_runtime"),
        key = "clear_overlay",
        value = function(_, kind, idx)
          cleared[#cleared + 1] = kind .. ":" .. tostring(idx)
        end,
      },
    }, function()
      local handled = visual_sync.sync_many(state, { overlay_indices = { 1 } })
      _assert_eq(handled, true, "sync_many should handle the overlay index")
    end)

    _assert_eq(#cleared, 1, "pending trigger should suppress the same-beat roadblock clear")
    _assert_eq(cleared[1], "mine:1", "only the mine overlay should clear")
  end)

  it("test_mine_overlay_sync_passes_deps_in_the_deps_slot_not_the_scale_slot", function()
    -- Regression (deploy log, 2026-07-12): 地雷 prefab moved from group to
    -- unit in Data/Prefab.lua. _spawn_mine_overlay called spawn_overlay with
    -- 7 args — deps landed in the scale slot. Harmless on the group path
    -- (scale ignored), but the unit path hands scale to the host as a
    -- Vector3, so the deps table would reach create_unit_with_scale.
    local prefab = require("Data.Prefab")
    local board = {
      has_roadblock = function() return false end,
      has_mine = function(_, idx) return idx == 1 end,
    }
    local runtime_sentinel = { host_runtime = {} }
    local state = {
      game = { board = board, turn = {} },
      board_scene = {},
      presentation_runtime = runtime_sentinel,
    }
    local spawn_args = nil

    _with_patches({
      {
        target = require("src.ui.render.anim.overlay_runtime"),
        key = "spawn_overlay",
        value = function(_, kind, idx, group_id, unit_id, pos, scale, deps)
          if kind == "mine" then
            spawn_args = { idx = idx, group_id = group_id, unit_id = unit_id,
              pos = pos, scale = scale, deps = deps }
          end
          return true
        end,
      },
      {
        target = require("src.ui.render.anim.overlay_compute"),
        key = "overlay_pos_for_tile",
        value = function() return { x = 0, y = 0, z = 0 } end,
      },
    }, function()
      local handled = visual_sync.sync_overlay_visual(state, 1)
      _assert_eq(handled, true, "mine overlay sync should handle valid board index")
    end)

    luassert.truthy(spawn_args ~= nil, "mine tile must spawn a mine overlay")
    _assert_eq(spawn_args.unit_id, prefab.unit and prefab.unit["地雷A"] or nil,
      "mine overlay should forward the 地雷A unit prefab key")
    _assert_eq(spawn_args.scale, nil,
      "mine overlay must not smuggle the deps table into the scale slot")
    _assert_eq(spawn_args.deps, runtime_sentinel,
      "mine overlay must pass presentation runtime in the deps slot")
  end)

  it("test_shared_deps_returns_the_presentation_runtime_carried_by_state", function()
    local shared = require("src.ui.render.board.visual_sync_shared")
    local runtime = { host = true }
    _assert_eq(shared.deps({ presentation_runtime = runtime }), runtime,
      "deps should return state.presentation_runtime")
    _assert_eq(shared.deps({}), nil, "deps should return nil when no runtime is present")
    _assert_eq(shared.deps(nil), nil, "deps should tolerate a nil state")
  end)

  it("test_sync_tile_visual_prefers_the_cached_tile_unit_over_the_scene_tile_unit", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = nil },
    })
    local cached_unit = { name = "cached" }
    local scene_unit = { name = "scene" }
    local state = {
      game = { board = board },
      tile_units = { [1] = cached_unit },
      board_scene = { tiles = { [1] = scene_unit } },
    }
    local rendered_unit = nil

    _with_patches({
      {
        target = require("src.ui.render.board.tile"),
        key = "render_tile",
        value = function(unit)
          rendered_unit = unit
        end,
      },
    }, function()
      local handled = visual_sync.sync_tile_visual(state, 1)
      _assert_eq(handled, true, "an existing tile unit should report the sync handled")
    end)

    _assert_eq(rendered_unit, cached_unit, "sync should render the cached tile unit, not the scene fallback")
  end)

  it("test_sync_tile_visual_renders_a_zero_component_rent_as_no_contiguous_rent", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10, price = 100 },
    })
    local game = { board = board }
    function game:find_player_by_id(player_id)
      if player_id == 10 then
        return { id = 10, name = "Ada" }
      end
      return nil
    end
    local state = {
      game = game,
      board_scene = { tiles = { [1] = { name = "u1" } } },
    }
    local rendered_rent = "unset"

    _with_patches({
      {
        target = require("src.ui.view.contiguous_count"),
        key = "build_rent_for_owner",
        value = function()
          return { [1] = 0 }
        end,
      },
      {
        target = require("src.ui.render.board.tile"),
        key = "render_tile",
        value = function(_unit, _tile_id, _owner_id, _owner_name, _level, contiguous_rent)
          rendered_rent = contiguous_rent
        end,
      },
    }, function()
      visual_sync.sync_tile_visual(state, 1)
    end)

    _assert_eq(rendered_rent, nil, "a zero-sum component should render without a contiguous rent badge")
  end)

  it("test_sync_tile_visual_forwards_a_positive_component_rent_to_the_renderer", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10, price = 100 },
    })
    local game = { board = board }
    function game:find_player_by_id(player_id)
      if player_id == 10 then
        return { id = 10, name = "Ada" }
      end
      return nil
    end
    local state = {
      game = game,
      board_scene = { tiles = { [1] = { name = "u1" } } },
    }
    local rendered_rent = "unset"

    _with_patches({
      {
        target = require("src.ui.view.contiguous_count"),
        key = "build_rent_for_owner",
        value = function()
          return { [1] = 1 }
        end,
      },
      {
        target = require("src.ui.render.board.tile"),
        key = "render_tile",
        value = function(_unit, _tile_id, _owner_id, _owner_name, _level, contiguous_rent)
          rendered_rent = contiguous_rent
        end,
      },
    }, function()
      visual_sync.sync_tile_visual(state, 1)
    end)

    _assert_eq(rendered_rent, 1, "a positive component rent should be forwarded to the renderer")
  end)

  it("test_sync_tile_visual_renders_level_0_when_the_tile_has_no_level", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = nil },
    })
    local state = {
      game = { board = board },
      board_scene = { tiles = { [1] = {} } },
    }
    local rendered_level = "unset"

    _with_patches({
      {
        target = require("src.ui.render.board.tile"),
        key = "render_tile",
        value = function(_unit, _tile_id, _owner_id, _owner_name, level)
          rendered_level = level
        end,
      },
    }, function()
      visual_sync.sync_tile_visual(state, 1)
    end)

    _assert_eq(rendered_level, 0, "a tile without a level should render at level 0")
  end)

  it("test_sync_tile_visual_clears_building_units_when_the_tile_has_no_level", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = nil },
    })
    local state = {
      game = { board = board },
      board_scene = { tiles = { [1] = {} }, buildings = { [1] = {} }, building_unit_groups = {} },
    }
    local events = {}

    _with_patches({
      { target = require("src.ui.render.board.tile"), key = "render_tile", value = function() end },
      {
        target = require("src.ui.render.board.building_effects"),
        key = "spawn_upgrade_building_units",
        value = function()
          events[#events + 1] = "spawn"
          return true
        end,
      },
      {
        target = require("src.ui.render.board.building_effects"),
        key = "clear_building_units",
        value = function()
          events[#events + 1] = "clear"
        end,
      },
    }, function()
      local handled = visual_sync.sync_tile_visual(state, 1)
      _assert_eq(handled, true, "the clear branch should report the sync handled")
    end)

    _assert_eq(events[1], "clear", "a level-0 tile should clear building units")
    _assert_eq(#events, 1, "a level-0 tile should not spawn building units")
  end)

  it("test_sync_tile_visual_spawns_building_units_when_the_tile_level_is_1", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = nil, level = 1 },
    })
    local state = {
      game = { board = board },
      board_scene = { tiles = { [1] = {} }, buildings = { [1] = {} }, building_unit_groups = {} },
    }
    local events = {}

    _with_patches({
      { target = require("src.ui.render.board.tile"), key = "render_tile", value = function() end },
      {
        target = require("src.ui.render.board.building_effects"),
        key = "spawn_upgrade_building_units",
        value = function()
          events[#events + 1] = "spawn"
          return false
        end,
      },
      {
        target = require("src.ui.render.board.building_effects"),
        key = "clear_building_units",
        value = function()
          events[#events + 1] = "clear"
        end,
      },
    }, function()
      local handled = visual_sync.sync_tile_visual(state, 1)
      _assert_eq(handled, true, "the spawn branch should still report handled via the tile unit fallback")
    end)

    _assert_eq(events[1], "spawn", "a level-1 tile should spawn building units")
    _assert_eq(#events, 1, "a level-1 tile should not clear building units")
  end)

  it("test_sync_tile_visual_skips_building_sync_when_only_part_of_the_building_scene_exists", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = nil, level = 2 },
    })
    local state = {
      game = { board = board },
      board_scene = { tiles = { [1] = {} }, buildings = { [1] = {} } }, -- no building_unit_groups
    }
    local events = {}

    _with_patches({
      { target = require("src.ui.render.board.tile"), key = "render_tile", value = function() end },
      {
        target = require("src.ui.render.board.building_effects"),
        key = "spawn_upgrade_building_units",
        value = function()
          events[#events + 1] = "spawn"
          return true
        end,
      },
      {
        target = require("src.ui.render.board.building_effects"),
        key = "clear_building_units",
        value = function()
          events[#events + 1] = "clear"
        end,
      },
    }, function()
      local handled = visual_sync.sync_tile_visual(state, 1)
      _assert_eq(handled, true, "an existing tile unit should still mark the sync handled")
    end)

    _assert_eq(#events, 0, "a partial building scene should neither spawn nor clear building units")
  end)

  it("test_sync_tile_visual_returns_false_for_a_nil_tile_id", function()
    _assert_eq(visual_sync.sync_tile_visual({}, nil), false, "a nil tile id should not be handled")
  end)

  it("test_sync_tile_visual_returns_false_when_the_board_scene_is_missing", function()
    local board = _build_board({
      { id = 1, type = "land" },
    })
    local state = { game = { board = board } } -- no board_scene
    _assert_eq(visual_sync.sync_tile_visual(state, 1), false, "a missing scene should short-circuit tile sync")
  end)

  it("test_sync_tile_visual_returns_false_when_the_tile_id_is_not_on_the_board", function()
    local board = _build_board({
      { id = 1, type = "land" },
    })
    local state = { game = { board = board }, board_scene = { tiles = {} } }
    _assert_eq(visual_sync.sync_tile_visual(state, 999), false, "an unknown tile id should not be handled")
  end)

  it("test_sync_overlay_visual_returns_false_for_a_nil_board_index", function()
    _assert_eq(visual_sync.sync_overlay_visual({}, nil), false, "a nil board index should not be handled")
  end)

  it("test_sync_overlay_visual_returns_false_when_the_board_scene_is_missing", function()
    local board = {
      has_roadblock = function() return false end,
      has_mine = function() return false end,
    }
    local state = { game = { board = board } } -- no board_scene
    _with_patches({
      { target = require("src.ui.render.anim.overlay_runtime"), key = "clear_overlay", value = function() end },
    }, function()
      _assert_eq(visual_sync.sync_overlay_visual(state, 1), false, "a missing scene should short-circuit overlay sync")
    end)
  end)

  it("test_sync_overlay_visual_clears_both_overlays_when_there_is_no_active_turn", function()
    local board = {
      has_roadblock = function() return false end,
      has_mine = function() return false end,
    }
    local state = { game = { board = board }, board_scene = {} } -- game.turn is nil
    local cleared = {}
    _with_patches({
      {
        target = require("src.ui.render.anim.overlay_runtime"),
        key = "clear_overlay",
        value = function(_scene, kind)
          cleared[#cleared + 1] = kind
        end,
      },
    }, function()
      _assert_eq(visual_sync.sync_overlay_visual(state, 1), true, "overlay sync should handle a valid board index")
    end)

    _assert_eq(#cleared, 2, "with no active turn both overlays should clear")
  end)

  it("test_sync_overlay_visual_clears_overlays_when_the_anim_queue_is_not_a_table", function()
    local board = {
      has_roadblock = function() return false end,
      has_mine = function() return false end,
    }
    -- turn is present but action_anim and action_anim_queue are nil
    local state = { game = { board = board, turn = {} }, board_scene = {} }
    local cleared = {}
    _with_patches({
      {
        target = require("src.ui.render.anim.overlay_runtime"),
        key = "clear_overlay",
        value = function(_scene, kind)
          cleared[#cleared + 1] = kind
        end,
      },
    }, function()
      visual_sync.sync_overlay_visual(state, 1)
    end)

    _assert_eq(#cleared, 2, "a nil anim queue should not suppress overlay clears")
  end)

  it("test_sync_overlay_visual_keeps_the_mine_overlay_while_a_matching_trigger_animation_plays", function()
    local board = {
      has_roadblock = function() return false end,
      has_mine = function() return false end,
    }
    local state = {
      game = {
        board = board,
        turn = {
          action_anim = { kind = "mine_trigger", tile_index = 1 },
          action_anim_queue = {},
        },
      },
      board_scene = {},
    }
    local cleared = {}
    _with_patches({
      {
        target = require("src.ui.render.anim.overlay_runtime"),
        key = "clear_overlay",
        value = function(_scene, kind)
          cleared[#cleared + 1] = kind
        end,
      },
    }, function()
      visual_sync.sync_overlay_visual(state, 1)
    end)

    _assert_eq(#cleared, 1, "only the roadblock overlay should clear")
    _assert_eq(cleared[1], "roadblock", "the mine overlay must persist while its trigger animation is active")
  end)

  it("test_sync_overlay_visual_spawns_the_roadblock_overlay_with_the_host_vector3_scale", function()
    local overlay_runtime = require("src.ui.render.anim.overlay_runtime")
    local module_path = "src.ui.render.board.visual_sync_overlay"
    local saved_module = package.loaded[module_path]
    local saved_vector3 = math.Vector3
    package.loaded[module_path] = nil
    math.Vector3 = function(x, y, z)
      return { x = x, y = y, z = z, _host_vector = true }
    end
    local overlay_module = require(module_path)
    math.Vector3 = saved_vector3
    package.loaded[module_path] = saved_module

    local board = {
      has_roadblock = function() return true end,
      has_mine = function() return false end,
    }
    local state = { game = { board = board, turn = {} }, board_scene = { tiles = {}, ground = { get_position = function() return math.Vector3(0.0, 0.0, 0.0) end } } }
    local spawned = nil

    _with_patches({
      {
        target = overlay_runtime,
        key = "spawn_overlay",
        value = function(_scene, kind, idx, _group, _unit, _pos, scale)
          if kind == "roadblock" then
            spawned = { idx = idx, scale = scale }
          end
        end,
      },
      { target = overlay_runtime, key = "clear_overlay", value = function() end },
    }, function()
      local handled = overlay_module.sync_overlay_visual(state, 1)
      _assert_eq(handled, true, "overlay sync should handle a roadblock tile")
    end)

    luassert.truthy(spawned ~= nil, "a roadblock tile should spawn the roadblock overlay")
    _assert_eq(spawned.idx, 1, "roadblock overlay should target the board index")
    _assert_eq(spawned.scale.x, 4.0, "roadblock overlay scale should be the 4.0 vector")
    _assert_eq(spawned.scale._host_vector, true,
      "roadblock scale should be the host Vector3, not the plain fallback table")
  end)

  it("test_sync_many_reports_handled_when_an_overlay_index_is_synced", function()
    local overlay_sync = require("src.ui.render.board.visual_sync_overlay")
    local handled
    _with_patches({
      { target = overlay_sync, key = "sync_overlay_visual", value = function() return true end },
    }, function()
      handled = visual_sync.sync_many({}, { overlay_indices = { 1 } })
    end)
    _assert_eq(handled, true, "an overlay index that syncs should make sync_many report handled")
  end)

  it("test_sync_many_reports_not_handled_when_overlay_sync_does_nothing", function()
    local overlay_sync = require("src.ui.render.board.visual_sync_overlay")
    local handled
    _with_patches({
      { target = overlay_sync, key = "sync_overlay_visual", value = function() return false end },
    }, function()
      handled = visual_sync.sync_many({}, { overlay_indices = { 1 } })
    end)
    _assert_eq(handled, false, "overlay indices that sync nothing should not mark sync_many handled")
  end)

  it("test_sync_many_reports_not_handled_when_tile_sync_does_nothing", function()
    local tile_sync = require("src.ui.render.board.visual_sync_tile")
    local handled
    _with_patches({
      { target = tile_sync, key = "sync_tile_visual", value = function() return false end },
    }, function()
      handled = visual_sync.sync_many({}, { tile_ids = { 1 } })
    end)
    _assert_eq(handled, false, "tile ids that sync nothing should not mark sync_many handled")
  end)

  it("test_sync_many_reports_handled_from_the_explicit_tile_ids", function()
    local tile_sync = require("src.ui.render.board.visual_sync_tile")
    local handled
    _with_patches({
      { target = tile_sync, key = "sync_tile_visual", value = function() return true end },
    }, function()
      handled = visual_sync.sync_many({}, { tile_ids = { 1 } })
    end)
    _assert_eq(handled, true, "an explicit tile id that syncs should make sync_many report handled")
  end)

  it("test_sync_many_dedupes_overlay_indices_before_syncing", function()
    local overlay_sync = require("src.ui.render.board.visual_sync_overlay")
    local calls = {}
    _with_patches({
      {
        target = overlay_sync,
        key = "sync_overlay_visual",
        value = function(_state, idx)
          calls[#calls + 1] = idx
          return true
        end,
      },
    }, function()
      visual_sync.sync_many({}, { overlay_indices = { 1, 1 } })
    end)
    _assert_eq(#calls, 1, "duplicate overlay indices should be normalized to a single sync")
  end)

  it("test_sync_many_surfaces_no_expanded_tiles_when_the_board_path_is_not_a_table", function()
    local state = { game = { board = { path = nil } } }
    local handled = visual_sync.sync_many(state, { affected_owner_ids = { 10 } })
    _assert_eq(handled, false, "a non-table board path should short-circuit owner expansion")
  end)

  -- ===== 迁自 test/property/test_contiguity.lua（#190, 测试极简化决策：property 车道退场，性质并入 behavior）=====
  do
    local property = require("test.support.property")

    -- Generate a random board: a path of land/non-land tiles with random owners and
    -- a random symmetric adjacency graph. The board exposes both read seams that
    -- contiguous_count understands (tile_lookup and get_tile_by_id) so the two
    -- counting paths under test share identical inputs.
    local OWNERS = { 10, 20, 30 }

    local function _gen_board(rng)
      local n = rng:int(1, 10)
      local tiles, lookup = {}, {}
      for id = 1, n do
        local is_land = rng:int(1, 4) > 1 -- ~75% land, rest non-land neighbours
        local owner
        if is_land and rng:bool() then
          owner = rng:pick(OWNERS) -- some land stays unowned (owner nil)
        end
        local tile = { id = id, type = is_land and "land" or "market", owner_id = owner }
        tiles[id] = tile
        lookup[id] = tile
      end
      local neighbors = {}
      for id = 1, n do
        neighbors[id] = {}
      end
      for id = 1, n do
        for jd = id + 1, n do
          if rng:int(1, 3) == 1 then -- sparse random symmetric edges
            neighbors[id][#neighbors[id] + 1] = jd
            neighbors[jd][#neighbors[jd] + 1] = id
          end
        end
      end
      local board = { path = tiles, tile_lookup = lookup, map = { neighbors = neighbors } }
      function board:get_tile_by_id(tile_id)
        return lookup[tile_id]
      end
      return { board = board, tiles = tiles, neighbors = neighbors }
    end

    -- Independent oracle: connected-component size of `owner`'s land tiles over the
    -- land-only adjacency graph, computed with a plain flood fill that shares no
    -- code with contiguous_count's BFS.
    local function _oracle_counts(case, owner)
      local tiles, neighbors = case.tiles, case.neighbors
      local function is_owned_land(id)
        local tile = tiles[id]
        return tile and tile.type == "land" and tile.owner_id == owner
      end
      local counts = {}
      for start_id in pairs(tiles) do
        if is_owned_land(start_id) and counts[start_id] == nil then
          local component, stack, seen = {}, { start_id }, { [start_id] = true }
          while #stack > 0 do
            local cur = stack[#stack]
            stack[#stack] = nil
            component[#component + 1] = cur
            for _, next_id in ipairs(neighbors[cur] or {}) do
              if not seen[next_id] and is_owned_land(next_id) and tiles[cur].type == "land" then
                seen[next_id] = true
                stack[#stack + 1] = next_id
              end
            end
          end
          for _, cid in ipairs(component) do
            counts[cid] = #component
          end
        end
      end
      return counts
    end

    it("test_for_tile_agrees_with_build_for_owner_for_every_land_tile", function()
      property.for_all(_gen_board, function(case)
        for _, owner in ipairs(OWNERS) do
          local swept = contiguous_count.build_for_owner(case.board, owner)
          for id, tile in pairs(case.tiles) do
            local per_tile = contiguous_count.for_tile(case.board, id, owner)
            if tile.type == "land" and tile.owner_id == owner then
              luassert.truthy(per_tile == swept[id], "for_tile must match build_for_owner for owned land tile " .. tostring(id)
                .. "; got " .. tostring(per_tile) .. " vs " .. tostring(swept[id]))
            else
              luassert.truthy(per_tile == 0, "for_tile must be 0 for tile " .. tostring(id) .. " not owned by " .. tostring(owner))
              luassert.truthy(swept[id] == nil, "build_for_owner must omit tile " .. tostring(id) .. " not owned by " .. tostring(owner))
            end
          end
        end
      end)
    end)

    it("test_both_counting_paths_match_an_independent_flood_fill_oracle", function()
      property.for_all(_gen_board, function(case)
        for _, owner in ipairs(OWNERS) do
          local expected = _oracle_counts(case, owner)
          local swept = contiguous_count.build_for_owner(case.board, owner)
          for id in pairs(case.tiles) do
            luassert.truthy(swept[id] == expected[id], "build_for_owner must match oracle for tile " .. tostring(id)
              .. "; got " .. tostring(swept[id]) .. " want " .. tostring(expected[id]))
            if expected[id] ~= nil then
              luassert.truthy(contiguous_count.for_tile(case.board, id, owner) == expected[id], "for_tile must match oracle for tile " .. tostring(id))
            end
          end
        end
      end)
    end)

    it("test_is_idempotent_repeated_counts_are_stable_once_land_neighbours_are_cached", function()
      property.for_all(_gen_board, function(case)
        for _, owner in ipairs(OWNERS) do
          local first = contiguous_count.build_for_owner(case.board, owner)
          -- The board now carries a cached land_neighbors map; a second sweep must
          -- read the cache (not rebuild) and return an identical result.
          luassert.truthy(case.board.land_neighbors ~= nil, "build_for_owner should cache land_neighbors on the board")
          local second = contiguous_count.build_for_owner(case.board, owner)
          for id, count in pairs(first) do
            luassert.truthy(second[id] == count, "cached sweep must repeat the first count for tile " .. tostring(id))
            luassert.truthy(contiguous_count.for_tile(case.board, id, owner) == count, "for_tile over the cached board must match build_for_owner for tile " .. tostring(id))
            luassert.truthy(count >= 1, "a counted tile must belong to a component of at least size 1")
          end
          for id in pairs(second) do
            luassert.truthy(first[id] ~= nil, "cached sweep must not invent a tile absent from the first sweep")
          end
        end
      end)
    end)
  end


  it("test_build_rent_for_owner_handles_nil_rent_per_tile", function()
    local board = _build_board({
      { id = 1, type = "land", owner_id = 10 },
      { id = 2, type = "land", owner_id = 10 },
    }, {
      [1] = { right = 2 },
      [2] = { left = 1 },
    })
    local rents = contiguous_count.build_rent_for_owner(board, 10, function(tile, cid)
      -- tile 1 returns nil, tile 2 returns 50
      if cid == 1 then return nil end
      return 50
    end)
    _assert_eq(rents[1], 50, "nil rent for tile 1 should default to 0 via or 0, total=0+50=50")
    _assert_eq(rents[2], 50, "same component rent total for tile 2")
  end)

  it("test_build_rent_for_owner_resolves_component_tile_via_get_tile_by_id_fallback", function()
    -- 构造不完整 tile_lookup：tile 2 不在 lookup 中，但 get_tile_by_id 可用
    local tiles = {
      { id = 1, type = "land", owner_id = 10, level = 1, price = 100 },
      { id = 2, type = "land", owner_id = 10, level = 0, price = 100 },
    }
    local lookup = { [1] = tiles[1] } -- tile 2 NOT in lookup
    local board = {
      path = tiles,
      tile_lookup = lookup,
      map = { neighbors = { [1] = { 2 }, [2] = { 1 } } },
    }
    function board:get_tile_by_id(tile_id)
      for _, t in ipairs(tiles) do
        if t.id == tile_id then return t end
      end
      return nil
    end

    -- build_rent_for_owner calls _component_tile which needs fallback for tile 2
    local rents = contiguous_count.build_rent_for_owner(board, 10, function(tile)
      if tile.level == 1 then return 100 end
      return 50
    end)

    _assert_eq(rents[1], 150, "component total rent should include tile resolved via get_tile_by_id fallback")
    _assert_eq(rents[2], 150, "tile 2 should also receive the component total")
  end)

end)
