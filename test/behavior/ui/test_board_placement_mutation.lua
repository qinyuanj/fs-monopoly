-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
-- board placement mutation 覆盖:build_snapshot 双缓冲、build_occupants 原位复用、
-- resolve_min_player_y 配置偏移、place_players 网格/单格/零间距/抬升各路径。
--
local placement = require("src.ui.render.board.placement")
local runtime_state = require("src.ui.state.runtime")
local move_anim = require("src.ui.render.move_anim")
local logger = require("src.foundation.log")

local function _assert_eq(actual, expected, message)
  luassert.truthy(actual == expected, (message or "assertion failed")
    .. " expected=" .. tostring(expected)
    .. " actual=" .. tostring(actual))
end

local function _ensure_vector3()
  if not math.Vector3 then
    function math.Vector3(x, y, z)
      return { x = x, y = y, z = z }
    end
  end
end

local function _with_patches(patches, fn)
  local originals = {}
  for index, patch in ipairs(patches) do
    originals[index] = patch.target[patch.key]
    patch.target[patch.key] = patch.value
  end
  local ok, result = pcall(fn)
  for index, patch in ipairs(patches) do
    patch.target[patch.key] = originals[index]
  end
  if not ok then
    error(result)
  end
  return result
end

local function _reload_with(module_name, overrides, fn)
  local original_module = package.loaded[module_name]
  local originals = {}
  for key, value in pairs(overrides or {}) do
    originals[key] = package.loaded[key]
    package.loaded[key] = value
  end
  package.loaded[module_name] = nil

  local ok, result = pcall(function()
    return fn(require(module_name))
  end)

  package.loaded[module_name] = original_module
  for key, value in pairs(originals) do
    package.loaded[key] = value
  end
  if not ok then
    error(result)
  end
  return result
end

local function _based(x, y, z)
  return setmetatable({ x = x, y = y, z = z }, {
    __add = function(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end,
  })
end

describe("TestBoardPlacementMutation", function()

  before_each(function()
    _ensure_vector3()
  end)

  it("test_build_snapshot_alternates_between_the_double_buffered_snapshot_tables", function()
    local players = { { id = "p1", position = 3 } }
    local first = placement.build_snapshot(players)
    local second = placement.build_snapshot(players)
    luassert.truthy(first ~= second, "consecutive snapshots should use distinct buffer tables")
    local third = placement.build_snapshot(players)
    luassert.truthy(third == first, "the third snapshot should reuse the first buffer")
  end)

  it("test_build_snapshot_encodes_position_and_eliminated_flag_per_player", function()
    local players = {
      { id = "alive", position = 3, eliminated = false },
      { id = "dead", position = 8, eliminated = true },
    }
    local snapshot = placement.build_snapshot(players)
    _assert_eq(snapshot.alive, "3:0", "living player encodes eliminated as 0")
    _assert_eq(snapshot.dead, "8:1", "eliminated player encodes eliminated as 1")
  end)

  it("test_compute_need_sync_stays_false_when_snapshot_matches_last_positions_and_nothing_pends", function()
    local state = {
      board_runtime = {
        board_last_positions = { p1 = "3:0" },
        board_sync_pending = false,
        follow_targets = {},
      },
    }
    local snapshot = { p1 = "3:0" }
    _assert_eq(placement.compute_need_sync(state, snapshot), false,
      "no pending sync and identical positions should not require a sync")
  end)

  it("test_build_occupants_appends_active_players_in_slot_order_and_skips_eliminated", function()
    local state = { tile_positions = { [3] = {}, [4] = {} } }
    local players = {
      { id = "a", position = 3 },
      { id = "b", position = 3 },
      { id = "c", position = 4, eliminated = true },
    }
    local occ = placement.build_occupants(state, players)
    luassert.truthy(occ[3] ~= nil, "shared tile should have an occupant list")
    _assert_eq(occ[3][1], "a", "first active occupant should take slot 1")
    _assert_eq(occ[3][2], "b", "second active occupant should take slot 2")
    _assert_eq(#occ[3], 2, "shared tile should list both active occupants")
    luassert.truthy(occ[4] == nil or #occ[4] == 0, "eliminated player should not be listed")
  end)

  it("test_build_occupants_clears_occupant_list_tables_in_place_and_reuses_them", function()
    local state = { tile_positions = { [5] = {} } }
    local players = { { id = "x", position = 5 } }
    local first = placement.build_occupants(state, players)
    local list_ref = first[5]
    luassert.truthy(list_ref ~= nil, "occupant list should exist after first build")
    local second = placement.build_occupants(state, players)
    luassert.truthy(second[5] == list_ref, "occupant list table should be cleared in place and reused")
  end)

  it("test_resolve_min_player_y_adds_the_configured_ground_offset_to_the_ground_height", function()
    local scene = { ground = { get_position = function() return { x = 0.0, y = 3.0, z = 0.0 } end } }
    -- resolve_min_player_y 随拆分迁到 placement_geometry(行为保持),配置覆写
    -- 须重载持有该函数的模块才能生效。
    local result = _reload_with("src.ui.render.board.placement_geometry", {
      ["src.config.gameplay.camera_follow"] = { player_min_ground_offset = 2.0 },
    }, function(geometry)
      return geometry.resolve_min_player_y(scene)
    end)
    _assert_eq(result, 5.0, "min player y should be ground y (3.0) plus configured offset (2.0)")
  end)

  it("test_place_players_lays_nine_occupants_on_a_centered_ceil_sqrt_grid", function()
    local saved_vector3 = math.Vector3
    function math.Vector3(x, y, z) return { x = x, y = y, z = z } end

    local placed = {}
    local units = {}
    local players = {}
    local occ = {}
    for n = 1, 9 do
      players[n] = { id = n, position = 7 }
      units[n] = { set_position = function(pos) placed[n] = pos end }
      occ[n] = n
    end

    _with_patches({
      { target = runtime_state, key = "set_follow_target_position", value = function() end },
      { target = move_anim, key = "stop_player_presentation", value = function() return {} end },
    }, function()
      local state = {
        tile_positions = { [7] = _based(10.0, 5.0, 20.0) },
        player_units = units,
      }
      placement.place_players(state, players, { [7] = occ }, 2.0, 0.0)
    end)

    -- per_row = ceil(sqrt(9)) = 3, spacing 2.0, centering start = -2.0.
    -- slot s -> row = floor((s-1)/3), col = (s-1)%3; ox = -2 + col*2, oz = -2 + row*2.
    local expected = {
      [1] = { x = 8.0, z = 18.0 },
      [2] = { x = 10.0, z = 18.0 },
      [3] = { x = 12.0, z = 18.0 },
      [4] = { x = 8.0, z = 20.0 },
      [5] = { x = 10.0, z = 20.0 },
      [6] = { x = 12.0, z = 20.0 },
      [7] = { x = 8.0, z = 22.0 },
      [8] = { x = 10.0, z = 22.0 },
      [9] = { x = 12.0, z = 22.0 },
    }
    for n = 1, 9 do
      _assert_eq(placed[n].x, expected[n].x, "slot " .. tostring(n) .. " x offset")
      _assert_eq(placed[n].z, expected[n].z, "slot " .. tostring(n) .. " z offset")
    end
    math.Vector3 = saved_vector3
  end)

  it("test_place_players_separates_occupants_for_a_fractional_spacing_above_zero", function()
    local saved_vector3 = math.Vector3
    function math.Vector3(x, y, z) return { x = x, y = y, z = z } end

    local placed = {}
    local units = {
      [1] = { set_position = function(pos) placed[1] = pos end },
      [2] = { set_position = function(pos) placed[2] = pos end },
    }
    _with_patches({
      { target = runtime_state, key = "set_follow_target_position", value = function() end },
      { target = move_anim, key = "stop_player_presentation", value = function() return {} end },
    }, function()
      local state = {
        tile_positions = { [2] = _based(4.0, 0.0, 6.0) },
        player_units = units,
      }
      placement.place_players(state,
        { { id = 1, position = 2 }, { id = 2, position = 2 } },
        { [2] = { 1, 2 } }, 1.0, 0.0)
    end)

    -- spacing 1.0 (> 0) so the offset guard does not collapse: per_row = 2, start = -0.5.
    _assert_eq(placed[1].x, 3.5, "slot 1 should shift half a spacing left of base")
    _assert_eq(placed[2].x, 4.5, "slot 2 should shift half a spacing right of base")
    math.Vector3 = saved_vector3
  end)

  it("test_place_players_collapses_offsets_to_base_for_non_positive_spacing", function()
    local saved_vector3 = math.Vector3
    function math.Vector3(x, y, z) return { x = x, y = y, z = z } end

    local placed = {}
    local units = {
      [1] = { set_position = function(pos) placed[1] = pos end },
      [2] = { set_position = function(pos) placed[2] = pos end },
    }
    _with_patches({
      { target = runtime_state, key = "set_follow_target_position", value = function() end },
      { target = move_anim, key = "stop_player_presentation", value = function() return {} end },
    }, function()
      local state = {
        tile_positions = { [1] = _based(4.0, 0.0, 6.0) },
        player_units = units,
      }
      placement.place_players(state,
        { { id = 1, position = 1 }, { id = 2, position = 1 } },
        { [1] = { 1, 2 } }, -2.0, 0.0)
    end)

    -- spacing -2.0 (<= 0) hits the guard, so both occupants land on the base tile.
    _assert_eq(placed[1].x, 4.0, "non-positive spacing should keep slot 1 on base x")
    _assert_eq(placed[2].x, 4.0, "non-positive spacing should keep slot 2 on base x")
    _assert_eq(placed[1].z, 6.0, "non-positive spacing should keep slot 1 on base z")
    _assert_eq(placed[2].z, 6.0, "non-positive spacing should keep slot 2 on base z")
    math.Vector3 = saved_vector3
  end)

  it("test_place_players_covers_grid_single_slot_zero_spacing_and_y_lift_offset_paths", function()
    local saved_vector3 = math.Vector3
    function math.Vector3(x, y, z) return { x = x, y = y, z = z } end

    local placed = {}
    local function unit_for(pid)
      return { set_position = function(pos) placed[pid] = pos end }
    end

    _with_patches({
      { target = runtime_state, key = "set_follow_target_position", value = function() end },
      { target = move_anim, key = "stop_player_presentation", value = function() return {} end },
    }, function()
      -- Two players sharing one tile: count=2, spacing>0 -> grid offsets diverge;
      -- base_y >= min_player_y -> y_offset 0.
      local state = {
        tile_positions = { [3] = _based(0.0, 5.0, 0.0) },
        player_units = { [1] = unit_for(1), [2] = unit_for(2) },
      }
      placement.place_players(state,
        { { id = 1, position = 3 }, { id = 2, position = 3 } },
        { [3] = { 1, 2 } }, 2.0, 0.0)
      luassert.truthy(placed[1].x ~= placed[2].x, "two-occupant grid should separate slot x")
      _assert_eq(placed[1].y, 5.0, "y_offset 0 should keep base y when base is above the floor")

      -- Single occupant: count<=1 -> zero offset; base_y < min -> y lifted.
      local state2 = {
        tile_positions = { [4] = _based(1.0, 1.0, 1.0) },
        player_units = { [1] = unit_for(1) },
      }
      placed = {}
      placement.place_players(state2, { { id = 1, position = 4 } }, { [4] = { 1 } }, 2.0, 10.0)
      _assert_eq(placed[1].x, 1.0, "single occupant should not be offset on x")
      _assert_eq(placed[1].y, 10.0, "y_offset should lift base up to the floor (1 + 9)")

      -- Zero spacing with multiple occupants: spacing<=0 -> zero offset.
      local state3 = {
        tile_positions = { [5] = _based(2.0, 8.0, 2.0) },
        player_units = { [1] = unit_for(1), [2] = unit_for(2) },
      }
      placed = {}
      placement.place_players(state3,
        { { id = 1, position = 5 }, { id = 2, position = 5 } },
        { [5] = { 1, 2 } }, 0.0, 0.0)
      _assert_eq(placed[1].x, 2.0, "zero spacing should collapse offsets to base x")
      _assert_eq(placed[2].x, 2.0, "zero spacing should collapse both occupants to base x")
    end)
    math.Vector3 = saved_vector3
  end)

  it("test_place_players_logs_the_stop_and_snap_line_when_move_anim_debug_logging_is_enabled", function()
    local saved_vector3 = math.Vector3
    function math.Vector3(x, y, z) return { x = x, y = y, z = z } end

    local captured = {}
    local original_print = _G.print
    rawset(_G, "print", function(...)
      local parts = {}
      for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
      end
      captured[#captured + 1] = table.concat(parts, " ")
    end)
    local ok, err = pcall(function()
      _with_patches({
        { target = runtime_state, key = "set_follow_target_position", value = function() end },
        { target = move_anim, key = "stop_player_presentation", value = function() return { motion_stop_path = "forced" } end },
        { target = logger, key = "anim_debug_enabled_provider", value = function() return true end },
      }, function()
        local state = {
          tile_positions = { [3] = _based(0.0, 5.0, 0.0) },
          player_units = { [1] = { set_position = function() end } },
        }
        placement.place_players(state, { { id = 1, position = 3 } }, { [3] = { 1 } }, 2.0, 0.0)
      end)
    end)
    rawset(_G, "print", original_print)
    math.Vector3 = saved_vector3
    if not ok then
      error(err)
    end

    local text = table.concat(captured, "\n")
    luassert.truthy(string.find(text, "board_refresh_stop_and_snap", 1, true) ~= nil, "debug log should record the stop-and-snap event")
    luassert.truthy(string.find(text, "motion_stop=forced", 1, true) ~= nil, "debug log should include the motion stop path")
  end)


end)
