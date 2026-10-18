require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- Branch/boundary coverage for src/rules/board/facing_policy.lua.
-- movement_spec already covers sync_move_dir's forced_move/clear value cases
-- and the resume_forward error contract; this pins the gaps:
--   * should_skip_inner_entry (scope.4) had no direct coverage at all,
--   * resolve_initial_facing (scope.5) only had its error path tested
--     (roadblock_spec stubs the function rather than exercising it),
--   * sync_move_dir_after_position_change's preserve branch, the
--     _set_move_dir changed/unchanged return value, and the invalid-mode guard.
local facing_policy = require("src.rules.board.facing_policy")

local function _assert_eq(a, b, msg)
  luassert.is.same(b, a, msg)
end

-- A minimal game whose set_player_status records writes onto player.status and
-- returns a sentinel so callers' return values can be observed.
local function _make_game(tiles)
  local calls = {}
  local game = {
    set_player_status = function(_, p, key, value)
      p.status = p.status or {}
      p.status[key] = value
      calls[#calls + 1] = { key = key, value = value }
      return { key = key, value = value }
    end,
    board = {
      get_tile = function(_, idx) return tiles and tiles[idx] or nil end,
    },
  }
  return game, calls
end

local function _player(move_dir)
  return { id = 1, status = { move_dir = move_dir } }
end

-- board carrying a single entry point at tile id 7.
local function _board(tile_at_position)
  return {
    map = { entry_points = { [7] = true } },
    get_tile = function(_, _pos) return tile_at_position end,
  }
end


describe("TestFacingPolicyClosure", function()
  it("test_preserve_mode_keeps_the_current_heading_and_reports_no_change", function()
    local g = _make_game()
    local p = _player("left")
    local changed = facing_policy.sync_move_dir_after_position_change(g, p, 1, "preserve")
    _assert_eq(p.status.move_dir, "left", "preserve must not alter move_dir")
    _assert_eq(changed, false, "setting move_dir to its current value reports no change")
  end)

  it("test_defaults_a_nil_mode_to_preserve", function()
    local g = _make_game()
    local p = _player("up")
    facing_policy.sync_move_dir_after_position_change(g, p, 1, nil)
    _assert_eq(p.status.move_dir, "up", "a nil mode behaves like preserve")
  end)

  it("test_forced_move_onto_market_overrides_heading_and_reports_the_change", function()
    local g = _make_game({ [9] = { type = "market" } })
    local p = _player("left")
    local changed = facing_policy.sync_move_dir_after_position_change(g, p, 9, "forced_move")
    _assert_eq(p.status.move_dir, "right", "market forces the default heading")
    _assert_eq(changed, true, "changing left -> right reports a change")
  end)

  it("test_forced_move_onto_market_is_a_no_op_when_already_facing_the_default", function()
    local g, calls = _make_game({ [9] = { type = "market" } })
    local p = _player("right")
    local changed = facing_policy.sync_move_dir_after_position_change(g, p, 9, "forced_move")
    _assert_eq(changed, false, "already facing right -> unchanged")
    _assert_eq(#calls, 0, "an unchanged heading must not write player status")
  end)

  it("test_forced_move_onto_an_ordinary_tile_preserves_the_heading_and_reports_no_change", function()
    local g = _make_game({ [3] = { type = "land" } })
    local p = _player("down")
    local changed = facing_policy.sync_move_dir_after_position_change(g, p, 3, "forced_move")
    _assert_eq(p.status.move_dir, "down", "a tile with no override preserves the heading")
    _assert_eq(changed, false, "an unchanged heading on an ordinary tile reports the _set_move_dir result, not nil")
  end)

  it("test_forced_move_onto_a_clearing_tile_drops_the_heading", function()
    local g = _make_game({ [4] = { type = "hospital" } })
    local p = _player("left")
    facing_policy.sync_move_dir_after_position_change(g, p, 4, "forced_move")
    _assert_eq(p.status.move_dir, nil, "hospital override clears the heading")
  end)

  it("test_forced_move_onto_the_mountain_drops_the_heading", function()
    local g = _make_game({ [6] = { type = "mountain" } })
    local p = _player("right")
    facing_policy.sync_move_dir_after_position_change(g, p, 6, "forced_move")
    _assert_eq(p.status.move_dir, nil, "mountain is a clearing tile type and drops the heading")
  end)

  it("test_clear_mode_drops_the_heading_and_resets_skip_next_inner_entry", function()
    local g = _make_game()
    local p = _player("left")
    local ret = facing_policy.sync_move_dir_after_position_change(g, p, 1, "clear")
    _assert_eq(p.status.move_dir, nil, "clear drops move_dir")
    _assert_eq(p.status.skip_next_inner_entry, false, "clear resets skip_next_inner_entry")
    _assert_eq(ret.key, "skip_next_inner_entry", "clear returns the skip-flag write result")
  end)

  it("test_rejects_an_unknown_sync_mode", function()
    local g = _make_game()
    local p = _player("left")
    local ok, err = pcall(facing_policy.sync_move_dir_after_position_change, g, p, 1, "bogus")
    _assert_eq(ok, false, "an invalid sync mode must assert")
    luassert.truthy(tostring(err):find("invalid move_dir sync mode", 1, true) ~= nil, "the assertion names the invalid-mode contract")
  end)

  it("test_sync_move_dir_after_position_change_rejects_a_nil_game", function()
    -- kills _require_sync_context's "missing game" -> nil (sync validates the
    -- context before _set_move_dir's own guard can run).
    luassert.has_error(function()
      facing_policy.sync_move_dir_after_position_change(nil, _player("left"), 1, "preserve")
    end, "missing game")
  end)

  it("test_set_move_dir_rejects_a_game_without_set_player_status", function()
    -- same sites: with a truthy game the `or` mutant passes the guard and the
    -- later method call raises a different error, not the guard message.
    luassert.has_error(function()
      facing_policy.sync_move_dir_after_position_change({}, _player("left"), 1, "preserve")
    end, "missing game.set_player_status")
  end)

  it("test_sync_move_dir_after_position_change_rejects_a_nil_player", function()
    -- kills _require_sync_context's "missing player" -> nil.
    local g = _make_game()
    luassert.has_error(function()
      facing_policy.sync_move_dir_after_position_change(g, nil, 1, "preserve")
    end, "missing player")
  end)

  it("test_sync_move_dir_after_position_change_rejects_a_nil_current_index", function()
    -- kills _require_sync_context's "missing current_index" -> nil.
    local g = _make_game()
    luassert.has_error(function()
      facing_policy.sync_move_dir_after_position_change(g, _player("left"), nil, "preserve")
    end, "missing current_index")
  end)

  it("test_should_skip_inner_entry_true_when_the_flagged_player_stands_on_an_entry_point_tile", function()
    local board = _board({ id = 7 })
    local player = { position = 5, status = { skip_next_inner_entry = true } }
    _assert_eq(facing_policy.should_skip_inner_entry(board, player), true,
      "flag set + tile is an entry point -> skip")
  end)

  it("test_should_skip_inner_entry_false_when_the_skip_flag_is_not_set", function()
    local board = _board({ id = 7 })
    local player = { position = 5, status = { skip_next_inner_entry = false } }
    _assert_eq(facing_policy.should_skip_inner_entry(board, player), false,
      "without the flag, never skip")
  end)

  it("test_should_skip_inner_entry_false_when_the_current_tile_is_not_an_entry_point", function()
    local board = _board({ id = 99 })
    local player = { position = 5, status = { skip_next_inner_entry = true } }
    _assert_eq(facing_policy.should_skip_inner_entry(board, player), false,
      "a non-entry tile id is not in entry_points")
  end)

  it("test_should_skip_inner_entry_false_when_the_current_tile_cannot_be_resolved", function()
    local board = _board(nil)
    local player = { position = 5, status = { skip_next_inner_entry = true } }
    _assert_eq(facing_policy.should_skip_inner_entry(board, player), false,
      "a nil tile cannot be an entry point")
  end)

  it("test_should_skip_inner_entry_false_when_the_board_has_no_entry_point_map", function()
    local board = { map = {}, get_tile = function() return { id = 7 } end }
    local player = { position = 5, status = { skip_next_inner_entry = true } }
    _assert_eq(facing_policy.should_skip_inner_entry(board, player), false,
      "missing entry_points map short-circuits to false")
  end)

  it("test_should_skip_inner_entry_false_for_a_player_with_no_position", function()
    local board = _board({ id = 7 })
    local player = { status = { skip_next_inner_entry = true } }
    _assert_eq(facing_policy.should_skip_inner_entry(board, player), false,
      "no position means nothing to skip")
  end)

  it("test_resolve_initial_facing_fresh_forward_always_starts_with_no_heading", function()
    _assert_eq(facing_policy.resolve_initial_facing("fresh_forward", _player("left"), { direction = "up" }),
      nil, "fresh_forward ignores any supplied direction")
  end)

  it("test_resolve_initial_facing_resume_forward_returns_the_explicit_direction", function()
    _assert_eq(facing_policy.resolve_initial_facing("resume_forward", _player(nil), { direction = "down" }),
      "down", "resume_forward echoes opts.direction")
  end)

  it("test_resolve_initial_facing_relative_forward_prefers_an_explicit_direction", function()
    _assert_eq(facing_policy.resolve_initial_facing("relative_forward", _player("left"), { direction = "right" }),
      "right", "an explicit direction wins over the player's heading")
  end)

  it("test_resolve_initial_facing_relative_backward_falls_back_to_the_player_s_recorded_heading", function()
    _assert_eq(facing_policy.resolve_initial_facing("relative_backward", _player("up"), {}),
      "up", "no explicit direction falls back to the player's move_dir")
  end)

  it("test_resolve_initial_facing_relative_forward_with_no_direction_and_no_heading_yields_nil", function()
    _assert_eq(facing_policy.resolve_initial_facing("relative_forward", _player(nil), nil),
      nil, "no direction anywhere resolves to nil")
  end)

  it("test_resolve_initial_facing_rejects_an_unknown_facing_mode", function()
    local ok, err = pcall(facing_policy.resolve_initial_facing, "sideways", _player("up"), {})
    _assert_eq(ok, false, "an invalid facing mode must assert")
    luassert.truthy(tostring(err):find("invalid facing mode", 1, true) ~= nil, "the assertion names the invalid-mode contract")
  end)

-- ===== 迁自 test/property/test_facing_policy.lua（#190, 测试极简化决策：property 车道退场，性质并入 behavior）=====
end)
do
  local property = require("test.support.property")

  -- Pool of direction-like values. The policy treats move_dir as an opaque token,
  -- so any distinct non-nil values exercise the pass-through paths; nil exercises
  -- the "no direction" fallbacks.
  local DIRECTIONS = { "left", "right", "up", "down", "forward", "backward" }

  local function _maybe_direction(rng)
    if rng:bool() then
      return rng:pick(DIRECTIONS)
    end
    return nil
  end

  -- player is sometimes absent / status-less so _player_move_dir's nil guards run.
  local function _gen_player(rng)
    local shape = rng:int(1, 3)
    if shape == 1 then
      return nil
    end
    if shape == 2 then
      return {}
    end
    return { status = { move_dir = _maybe_direction(rng) } }
  end

  local function _player_move_dir(player)
    local status = player and player.status or nil
    return status and status.move_dir or nil
  end

  describe("TestFacingPolicyClosure", function()
    it("test_prop_fresh_forward_resolves_to_nil_for_any_player_and_opts_direction", function()
      property.for_all(function(rng)
        return { player = _gen_player(rng), direction = _maybe_direction(rng) }
      end, function(case)
        local result = facing_policy.resolve_initial_facing("fresh_forward", case.player, {
          direction = case.direction,
        })
        luassert.truthy(result == nil, "fresh_forward must ignore inputs and return nil, got " .. tostring(result))
      end)
    end)

    it("test_prop_resume_forward_round_trips_opts_direction_unchanged", function()
      property.for_all(function(rng)
        return { player = _gen_player(rng), direction = rng:pick(DIRECTIONS) }
      end, function(case)
        local result = facing_policy.resolve_initial_facing("resume_forward", case.player, {
          direction = case.direction,
        })
        luassert.truthy(result == case.direction, "resume_forward must echo opts.direction " .. tostring(case.direction) .. ", got " .. tostring(result))
      end)
    end)

    it("test_prop_resume_forward_without_opts_direction_is_rejected", function()
      property.for_all(_gen_player, function(player)
        local ok = pcall(facing_policy.resolve_initial_facing, "resume_forward", player, {})
        luassert.truthy(not ok, "resume_forward must require opts.direction")
      end)
    end)

    it("test_prop_relative_modes_prefer_opts_direction_else_fall_back_to_the_player_s_move_dir", function()
      property.for_all(function(rng)
        return {
          mode = rng:pick({ "relative_forward", "relative_backward" }),
          player = _gen_player(rng),
          direction = _maybe_direction(rng),
        }
      end, function(case)
        local result = facing_policy.resolve_initial_facing(case.mode, case.player, {
          direction = case.direction,
        })
        local expected = case.direction
        if expected == nil then
          expected = _player_move_dir(case.player)
        end
        luassert.truthy(result == expected, "relative mode expected " .. tostring(expected) .. ", got " .. tostring(result))
      end)
    end)

    it("test_prop_opts_defaults_to_empty_so_a_nil_opts_behaves_like_no_direction", function()
      property.for_all(function(rng)
        return { mode = rng:pick({ "relative_forward", "relative_backward" }), player = _gen_player(rng) }
      end, function(case)
        local result = facing_policy.resolve_initial_facing(case.mode, case.player)
        luassert.truthy(result == _player_move_dir(case.player), "nil opts must resolve to the player's move_dir, got " .. tostring(result))
      end)
    end)

    it("test_prop_rejects_any_mode_outside_the_valid_set", function()
      property.for_all(function(rng)
        -- Random tokens that are never one of the four valid modes.
        return "mode_" .. tostring(rng:int(0, 1000000)) .. (rng:bool() and "" or "_x")
      end, function(mode)
        local ok = pcall(facing_policy.resolve_initial_facing, mode, nil, {})
        luassert.truthy(not ok, "invalid mode " .. tostring(mode) .. " must be rejected")
      end)
    end)

  -- Board where tile index i carries id i; entry_points holds a random subset of
  -- those ids. Positions may run past the board so get_tile can return nil.
  end)
  local function _gen_case(rng)
    local tile_count = rng:int(1, 8)
    local entry_points = {}
    for id = 1, tile_count do
      if rng:bool() then
        entry_points[id] = true
      end
    end
    return {
      tile_count = tile_count,
      entry_points = entry_points,
      position = rng:int(1, tile_count + 2),
      has_map = rng:bool(),
      skip = rng:bool(),
      has_status = rng:bool(),
    }
  end

  local function _build_board(case)
    local path = {}
    for i = 1, case.tile_count do
      path[i] = { id = i }
    end
    local map = nil
    if case.has_map then
      map = { entry_points = case.entry_points }
    end
    return {
      map = map,
      get_tile = function(_, idx) return path[idx] end,
    }
  end

  local function _build_player(case)
    local status = nil
    if case.has_status then
      status = { skip_next_inner_entry = case.skip }
    end
    return { position = case.position, status = status }
  end

  describe("TestFacingPolicyClosure", function()
    it("test_prop_returns_true_exactly_when_the_skip_flag_is_set_on_an_entry_point_tile", function()
      property.for_all(_gen_case, function(case)
        local board = _build_board(case)
        local player = _build_player(case)

        local result = facing_policy.should_skip_inner_entry(board, player)

        local tile = board:get_tile(case.position)
        local flag_set = case.has_status and case.skip == true
        local on_entry_point = case.has_map and tile ~= nil and case.entry_points[tile.id] ~= nil
        local expected = flag_set and on_entry_point

        luassert.truthy(result == expected, "expected " .. tostring(expected) .. ", got " .. tostring(result))
      end)
    end)

    it("test_prop_never_skips_when_the_skip_flag_is_absent_or_false", function()
      property.for_all(_gen_case, function(case)
        case.skip = false
        local result = facing_policy.should_skip_inner_entry(_build_board(case), _build_player(case))
        luassert.truthy(result == false, "no skip flag must never skip, got " .. tostring(result))
      end)
    end)

    it("test_prop_is_false_for_any_missing_structural_prerequisite", function()
      property.for_all(function(rng)
        return { missing = rng:pick({ "board", "map", "player", "position" }) }
      end, function(case)
        local board = { map = { entry_points = { [1] = true } }, get_tile = function(_, _) return { id = 1 } end }
        local player = { position = 1, status = { skip_next_inner_entry = true } }
        if case.missing == "board" then board = nil end
        if case.missing == "map" then board.map = nil end
        if case.missing == "player" then player = nil end
        if case.missing == "position" then player.position = nil end
        luassert.truthy(facing_policy.should_skip_inner_entry(board, player) == false, "missing " .. case.missing .. " must yield false")
      end)
    end)
  end)
end
