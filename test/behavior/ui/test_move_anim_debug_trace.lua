-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local move_anim = require("src.ui.render.move_anim")
local rt = require("src.ui.render.move_anim.runtime")
local debug_alias = require("src.ui.render.move_anim.debug")
local support = require("test.support.move_anim_support")

local function _assert_eq(actual, expected, message) luassert.is.equal(expected, actual, message) end
local _with_patches = support.with_patches

local function _scene(tile_count, unit)
  return support.new_scene_with_linear_tiles(tile_count, {
    units_by_player_id = { [1] = unit },
  })
end

-- Runs `fn` with move-anim debug logging on, returning every logged line as
-- { tag = <event>, fields = { "k=v", ... } }.
local function _capture_debug_log(fn)
  local logged = {}
  _with_patches({
    { target = debug_alias, key = "enabled", value = function() return true end },
    { target = debug_alias, key = "debug_log", value = function(tag, ...)
      logged[#logged + 1] = { tag = tag, fields = { ... } }
    end },
  }, function()
    fn()
  end)
  return logged
end

local function _lines_tagged(logged, tag)
  local out = {}
  for _, line in ipairs(logged) do
    if line.tag == tag then
      out[#out + 1] = line
    end
  end
  return out
end

local function _has_field(line, field)
  for _, value in ipairs(line.fields) do
    if value == field then
      return true
    end
  end
  return false
end

describe("TestMoveAnimDebugTrace", function()

  it("test_logs_the_sequence_start_with_step_count_and_token", function()
    local unit = support.new_unit_spy()
    local scene = _scene(2, unit)
    local logged = _capture_debug_log(function()
      support.capture_scheduled_callbacks(function()
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 31,
          from_index = 1,
          to_index = 2,
          direction = { x = 1, y = 0, z = 0 },
        })
      end)
    end)

    local starts = _lines_tagged(logged, "play_sequence_start")
    _assert_eq(#starts, 1, "a sequence should log exactly one start line")
    luassert.truthy(_has_field(starts[1], "seq=31"), "the start line should carry the sequence id")
    luassert.truthy(_has_field(starts[1], "step_count=1"), "the start line should carry the step count")
    luassert.truthy(_has_field(starts[1], "token=1:31"), "the start line should carry the sequence token")
    luassert.truthy(_has_field(starts[1], "visited=nil"), "a move without a visited path should log visited=nil")
  end)

  it("test_logs_the_visited_path_when_the_move_has_one", function()
    local unit = support.new_unit_spy()
    local scene = _scene(3, unit)
    local logged = _capture_debug_log(function()
      support.capture_scheduled_callbacks(function()
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 32,
          from_index = 1,
          to_index = 3,
          visited = { 2, 3 },
          direction = { x = 1, y = 0, z = 0 },
        })
      end)
    end)

    local starts = _lines_tagged(logged, "play_sequence_start")
    luassert.truthy(_has_field(starts[1], "visited=2,3"), "the start line should carry the visited path")
    luassert.truthy(_has_field(starts[1], "step_count=2"), "a two-hop visited path should report two steps")
  end)

  it("test_logs_each_scheduled_step_and_its_execution", function()
    local unit = support.new_unit_spy()
    local scene = _scene(3, unit)
    local scheduled
    local logged = _capture_debug_log(function()
      scheduled = support.capture_scheduled_callbacks(function()
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 33,
          from_index = 1,
          to_index = 3,
          visited = { 2, 3 },
          direction = { x = 1, y = 0, z = 0 },
        })
      end)
    end)

    _assert_eq(#_lines_tagged(logged, "step_schedule"), 2, "both steps should log a schedule line")
    _assert_eq(#_lines_tagged(logged, "step_execute"), 1, "only the immediate step should execute so far")

    local executed = _capture_debug_log(function()
      scheduled[1].fn()
    end)
    local step_lines = _lines_tagged(executed, "step_execute")
    _assert_eq(#step_lines, 1, "firing the delayed step should log its execution")
    luassert.truthy(_has_field(step_lines[1], "from=2"), "the delayed step should run from the second tile")
    luassert.truthy(_has_field(step_lines[1], "to=3"), "the delayed step should run to the third tile")
  end)

  it("test_logs_a_step_skip_when_the_token_went_stale", function()
    local unit, calls = support.new_unit_spy()
    local scene = _scene(3, unit)
    local scheduled
    _capture_debug_log(function()
      scheduled = support.capture_scheduled_callbacks(function()
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 34,
          from_index = 1,
          to_index = 3,
          visited = { 2, 3 },
          direction = { x = 1, y = 0, z = 0 },
        })
      end)
    end)
    local moves_before = #calls

    local logged = _capture_debug_log(function()
      rt.set_active_token(scene, 1, "stale_token_override")
      scheduled[1].fn()
    end)

    local skips = _lines_tagged(logged, "step_skip_stale_token")
    _assert_eq(#skips, 1, "a stale token should log the skipped step")
    luassert.truthy(_has_field(skips[1], "seq=34"), "the skip line should carry the sequence id")
    _assert_eq(#calls, moves_before, "a stale step should not move the unit")
  end)

  it("test_logs_the_finish_stop_with_the_motion_and_anim_stop_paths", function()
    local unit = support.new_unit_spy()
    local scene = _scene(2, unit)
    local scheduled
    local logged = _capture_debug_log(function()
      scheduled = support.capture_scheduled_callbacks(function()
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 35,
          from_index = 1,
          to_index = 2,
          direction = { x = 1, y = 0, z = 0 },
        })
      end)
      scheduled[#scheduled].fn()
    end)

    local stops = _lines_tagged(logged, "finish_stop")
    _assert_eq(#stops, 1, "the finish callback should log exactly one stop line")
    luassert.truthy(_has_field(stops[1], "seq=35"), "the stop line should carry the sequence id")
    luassert.truthy(_has_field(stops[1], "motion_stop=stop_move"), "the stop line should name the motion stop path")
    luassert.truthy(_has_field(stops[1], "anim_stop=stop_anim"), "the stop line should name the anim stop path")
  end)

  it("test_logs_none_for_a_finish_stop_that_found_no_host_stop_method", function()
    local unit = { start_move_by_direction = function() end }
    local scene = _scene(2, unit)
    local scheduled
    local logged = _capture_debug_log(function()
      scheduled = support.capture_scheduled_callbacks(function()
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 36,
          from_index = 1,
          to_index = 2,
          direction = { x = 1, y = 0, z = 0 },
        })
      end)
      scheduled[#scheduled].fn()
    end)

    local stops = _lines_tagged(logged, "finish_stop")
    luassert.truthy(_has_field(stops[1], "motion_stop=none"), "a unit with no stop method should log motion_stop=none")
    luassert.truthy(_has_field(stops[1], "anim_stop=none"), "a unit with no anim method should log anim_stop=none")
  end)

  it("test_logs_the_sequence_lock_release_with_its_reason", function()
    local unit = support.new_unit_spy()
    local scene = _scene(2, unit)
    local scheduled
    local logged = _capture_debug_log(function()
      scheduled = support.capture_scheduled_callbacks(function()
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 37,
          from_index = 1,
          to_index = 2,
          direction = { x = 1, y = 0, z = 0 },
        })
      end)
      scheduled[#scheduled].fn()
    end)

    local releases = _lines_tagged(logged, "sequence_lock_release")
    _assert_eq(#releases, 1, "finishing a sequence should log one lock release")
    luassert.truthy(_has_field(releases[1], "seq=37"), "the release line should carry the sequence id")
    luassert.truthy(_has_field(releases[1], "token=1:37"), "the release line should carry the token")
    luassert.truthy(_has_field(releases[1], "reason=sequence_finished"), "the release line should carry the reason")
  end)

  it("test_logs_the_replaced_sequence_lock_release", function()
    local unit = support.new_unit_spy()
    local scene = _scene(3, unit)
    local logged = _capture_debug_log(function()
      support.capture_scheduled_callbacks(function()
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 38,
          from_index = 1,
          to_index = 2,
          direction = { x = 1, y = 0, z = 0 },
        })
        move_anim.play_sequence(scene, {
          player_id = 1,
          seq = 39,
          from_index = 2,
          to_index = 3,
          direction = { x = 1, y = 0, z = 0 },
        })
      end)
    end)

    local releases = _lines_tagged(logged, "sequence_lock_release")
    _assert_eq(#releases, 1, "replacing a live sequence should release the old lock once")
    luassert.truthy(_has_field(releases[1], "reason=sequence_replaced"), "the replaced lock should log its reason")
    luassert.truthy(_has_field(releases[1], "seq=38"), "the replaced lock should name the old sequence")
  end)

end)
describe("TestMoveAnimZeroLengthSequence", function()

  it("test_schedules_nothing_when_the_move_covers_no_distance", function()
    local unit, calls = support.new_unit_spy()
    local scene = _scene(2, unit)

    local total
    local scheduled = support.capture_scheduled_callbacks(function()
      total = move_anim.play_sequence(scene, {
        player_id = 1,
        seq = 41,
        from_index = 2,
        to_index = 2,
        direction = { x = 1, y = 0, z = 0 },
      })
    end)

    _assert_eq(total, 0, "a move to the current tile should take no time")
    _assert_eq(#scheduled, 0, "a zero-length move should schedule neither steps nor a finish stop")
    _assert_eq(#calls, 0, "a zero-length move should never touch the unit")
    _assert_eq(rt.get_active_sequence(scene, 1), nil, "a zero-length move should not claim a sequence lock")
  end)

  it("test_does_not_open_the_panel_interrupt_window_for_a_zero_length_move", function()
    local unit = support.new_unit_spy()
    local scene = _scene(2, unit)
    local state = { ui = {} }

    support.capture_scheduled_callbacks(function()
      move_anim.play_sequence(scene, {
        state = state,
        player_id = 1,
        seq = 42,
        from_index = 2,
        to_index = 2,
        direction = { x = 1, y = 0, z = 0 },
      })
    end)

    _assert_eq(state.ui.move_active, nil,
      "a zero-length move should not open a panel-interrupt move window")
  end)

  it("test_opens_and_closes_the_panel_interrupt_window_across_a_real_move", function()
    local unit = support.new_unit_spy()
    local scene = _scene(2, unit)
    local state = { ui = {} }

    local scheduled = support.capture_scheduled_callbacks(function()
      move_anim.play_sequence(scene, {
        state = state,
        player_id = 1,
        seq = 43,
        from_index = 1,
        to_index = 2,
        direction = { x = 1, y = 0, z = 0 },
      })
    end)
    _assert_eq(state.ui.move_active, true, "starting a real move should open the panel-interrupt window")

    scheduled[#scheduled].fn()
    _assert_eq(state.ui.move_active, false, "finishing the move should close the panel-interrupt window")
  end)
end)
describe("TestMoveAnimDebugTrace", function()
  it("test_logs_placeholder_fields_when_the_released_sequence_has_no_meta", function()
    -- kills _log_sequence_lock_release 的 "nil"/"none" fallback 换 nil:
    -- entry 缺 seq/token、reason 缺省时必须落到占位文本而不是空串。
    local logged = _capture_debug_log(function()
      rt.release_sequence_lock({}, 1, { lock_released = false }, nil)
    end)

    local releases = _lines_tagged(logged, "sequence_lock_release")
    _assert_eq(#releases, 1, "releasing without meta should log one release line")
    luassert.truthy(_has_field(releases[1], "seq=nil"), "the release line should carry the seq placeholder")
    luassert.truthy(_has_field(releases[1], "token=nil"), "the release line should carry the token placeholder")
    luassert.truthy(_has_field(releases[1], "reason=none"), "the release line should carry the none reason placeholder")
  end)

  it("test_build_token_marks_a_missing_sequence_as_no_seq", function()
    -- kills build_token 的 `seq or "no_seq"` or->and:缺 seq 时 token 必须带
    -- no_seq 标记而不是 nil 文本。
    local token = rt.build_token(7, nil)
    _assert_eq(token, "7:no_seq", "a missing seq should be marked as no_seq in the token")
  end)

end)
