-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
local seq_builder = require("src.ui.render.move_anim.sequence_builder")
local shared_support = require("test.support.shared_support")
local vec3 = require("test.fixtures.vec3")
local runtime_constants = require("src.config.gameplay.runtime_constants")
local runtime_state = require("src.ui.state.runtime")

local function _assert_eq(actual, expected, message) luassert.is.equal(expected, actual, message) end
local _with_patches = shared_support.with_patches

local function _scene_between(a, b)
  return {
    tiles = {
      { get_position = function() return vec3.with_sub_length(a.x, a.y, a.z) end },
      { get_position = function() return vec3.with_sub_length(b.x, b.y, b.z) end },
    },
  }
end

describe("TestMoveAnimSequenceBuilderFormatVisited", function()

  it("test_formats_a_visited_path_as_a_comma_joined_list", function()
    _assert_eq(seq_builder.format_visited({ 3, 4, 5 }), "3,4,5",
      "a visited path should be joined with commas for the debug log")
  end)

  it("test_stringifies_each_visited_entry", function()
    _assert_eq(seq_builder.format_visited({ 1 }), "1",
      "a single-entry visited path should format without a separator")
  end)

  it("test_formats_an_empty_visited_path_as_nil", function()
    _assert_eq(seq_builder.format_visited({}), "nil",
      "an empty visited path should read as nil in the debug log")
  end)

  it("test_formats_a_missing_visited_path_as_nil", function()
    _assert_eq(seq_builder.format_visited(nil), "nil",
      "a missing visited path should read as nil in the debug log")
  end)

  it("test_formats_a_non_table_visited_path_as_nil", function()
    _assert_eq(seq_builder.format_visited("3,4"), "nil",
      "a non-table visited path should read as nil rather than leak its value")
  end)

end)
describe("TestMoveAnimSequenceBuilderDirection", function()

  it("test_prefers_an_explicit_direction", function()
    local explicit = { x = 1, y = 0, z = 0 }
    _assert_eq(seq_builder.resolve_direction({ direction = explicit, steps = -3 }), explicit,
      "an explicit direction should win over the step sign")
  end)

  it("test_resolves_a_backward_direction_from_negative_steps", function()
    local dir = seq_builder.resolve_direction({ steps = -2 })
    luassert.truthy(dir ~= nil, "negative steps should resolve to a direction")
    _assert_eq(dir.z, 1, "negative steps should face the right vector")
  end)

  it("test_resolves_a_forward_direction_from_positive_steps", function()
    local dir = seq_builder.resolve_direction({ steps = 2 })
    luassert.truthy(dir ~= nil, "positive steps should resolve to a direction")
    _assert_eq(dir.z, -1, "positive steps should face the left vector")
  end)

  it("test_resolves_no_direction_for_zero_or_missing_steps", function()
    _assert_eq(seq_builder.resolve_direction({ steps = 0 }), nil,
      "zero steps should not resolve a direction")
    _assert_eq(seq_builder.resolve_direction({}), nil,
      "a context without steps should not resolve a direction")
  end)


end)
describe("TestMoveAnimSequenceBuilderStepCalc", function()

  it("test_calc_step_vector_returns_zero_vector_for_zero_length", function()
    -- 杀 L20 len<=0 的 <=->< 与 L21 _zero_vector()->nil:同位置(零长)必须返回
    -- 零向量 dir 与 len 0——变异要么 div-by-zero(nan)要么 nil。
    local scene = _scene_between({ x = 1, y = 2, z = 3 }, { x = 1, y = 2, z = 3 })
    local dir, len = seq_builder.calc_step_vector(scene, 1, 2)
    _assert_eq(len, 0, "zero-length hop should report len 0")
    _assert_eq(dir ~= nil, true, "zero-length hop should still return a zero vector")
    _assert_eq(dir.x, 0, "zero-length dir x should be 0")
    _assert_eq(dir.y, 0, "zero-length dir y should be 0")
    _assert_eq(dir.z, 0, "zero-length dir z should be 0")
  end)

  it("test_calc_step_vector_normalizes_direction", function()
    -- 杀 L23 的 dir 计算 ->nil 与三个 /->*:dist=(0,3,4) len=5 时 dir 必须归一化到
    -- (0,0.6,0.8);乘变异会给 (0,15,20)。y/z 取非零值,零分量上 /->* 不可观测。
    local scene = _scene_between({ x = 0, y = 0, z = 0 }, { x = 0, y = 3, z = 4 })
    local dir, len = seq_builder.calc_step_vector(scene, 1, 2)
    _assert_eq(len, 5, "hop length should be the euclidean distance")
    _assert_eq(dir ~= nil, true, "dir should be present for a positive length")
    _assert_eq(dir.x, 0, "dir x should be normalized to 0")
    _assert_eq(dir.y, 0.6, "dir y should be normalized to 3/5")
    _assert_eq(dir.z, 0.8, "dir z should be normalized to 4/5")
  end)

  it("test_calc_step_vector_sub_length_hop_still_normalizes", function()
    -- 杀 L20 的 0->1:len∈(0,1] 时不得落进零长分支——dir 必须归一化而非零向量。
    local scene = _scene_between({ x = 0, y = 0, z = 0 }, { x = 0.5, y = 0, z = 0 })
    local dir, len = seq_builder.calc_step_vector(scene, 1, 2)
    _assert_eq(len, 0.5, "sub-one hop should report its true length")
    _assert_eq(dir.x, 1, "sub-one hop should still normalize the direction")
  end)

end)
describe("TestMoveAnimSequenceBuilderStepTime", function()

  it("test_calc_step_time_uses_walk_speed_ratio", function()
    -- 杀 L35 /->*:len=4、walk_speed=2 时时间必须为 2(乘变异给 8)。
    _with_patches({
      { target = runtime_constants, key = "walk_speed", value = 2 },
    }, function()
      local scene = _scene_between({ x = 0, y = 0, z = 0 }, { x = 4, y = 0, z = 0 })
      local t = seq_builder.calc_step_time(scene, 1, 2)
      _assert_eq(t, 2, "step time should be len / walk_speed")
    end)
  end)

  it("test_calc_step_time_falls_back_to_zero_without_walk_speed", function()
    -- 杀 L31 `or 0` 的 0->1:walk_speed 缺省时不得用 1 兜底(会给出非零时间)。
    _with_patches({
      { target = runtime_constants, key = "walk_speed", value = nil },
    }, function()
      local scene = _scene_between({ x = 0, y = 0, z = 0 }, { x = 4, y = 0, z = 0 })
      local t = seq_builder.calc_step_time(scene, 1, 2)
      _assert_eq(t, 0, "missing walk_speed should fall back to 0 time")
    end)
  end)

  it("test_calc_step_time_zero_walk_speed_returns_zero", function()
    -- 杀 L32 <=->< 与 L33 return 0 的 0->1:walk_speed=0 时必须返回 0,
    -- 不能算 len/0(inf)也不能返回 1。
    _with_patches({
      { target = runtime_constants, key = "walk_speed", value = 0 },
    }, function()
      local scene = _scene_between({ x = 0, y = 0, z = 0 }, { x = 4, y = 0, z = 0 })
      local t = seq_builder.calc_step_time(scene, 1, 2)
      _assert_eq(t, 0, "zero walk_speed should short-circuit to 0 time")
    end)
  end)

  it("test_calc_step_time_unit_walk_speed_keeps_length", function()
    -- 杀 L32 的 0->1:walk_speed=1 是合法速度,不得被 <=1 截断成 0。
    _with_patches({
      { target = runtime_constants, key = "walk_speed", value = 1 },
    }, function()
      local scene = _scene_between({ x = 0, y = 0, z = 0 }, { x = 4, y = 0, z = 0 })
      local t = seq_builder.calc_step_time(scene, 1, 2)
      _assert_eq(t, 4, "unit walk_speed should keep the length as the time")
    end)
  end)

  it("test_calc_step_time_sub_one_length_is_not_truncated", function()
    -- 杀 L28 的 0->1:len∈(0,1] 时不得被零长分支截成 0。
    _with_patches({
      { target = runtime_constants, key = "walk_speed", value = 2 },
    }, function()
      local scene = _scene_between({ x = 0, y = 0, z = 0 }, { x = 0.5, y = 0, z = 0 })
      local t = seq_builder.calc_step_time(scene, 1, 2)
      _assert_eq(t, 0.25, "sub-one length should still divide by walk_speed")
    end)
  end)

end)
describe("TestMoveAnimSequenceBuilderSteps", function()

  local function _constant_step_fn(value)
    return function()
      return value
    end
  end

  it("test_build_steps_skips_zero_step_time_steps", function()
    -- 杀 L86 step_time<=0 的 <=-><:零耗时步骤不得入列。
    local steps = seq_builder.build_steps(
      { tiles = {} },
      1,
      2,
      nil,
      {},
      _constant_step_fn(0)
    )
    _assert_eq(#steps, 0, "zero step time should produce no steps")
  end)

  it("test_build_steps_single_visited_entry_uses_direct_hop", function()
    -- 杀 L94 #visited<=1 的 <=->< 与 1->0:visited 长度 1 且首元素不是终点时,
    -- 必须走直接 from->to,不能误用 visited 表首元素。
    local steps = seq_builder.build_steps(
      { tiles = {} },
      1,
      2,
      { 9 },
      {},
      _constant_step_fn(1)
    )
    _assert_eq(#steps, 1, "one step should be produced")
    _assert_eq(steps[1].from, 1, "step should start at from_index")
    _assert_eq(steps[1].to, 2, "single visited entry should still hop directly to to_index")
  end)

end)
describe("TestMoveAnimSequenceBuilderFollow", function()

  it("test_publish_follow_target_requires_state_player_and_position", function()
    -- 杀 L128 两个 and->or 与 L138 return false->true:任一参数缺省必须拒绝发布。
    local ok = seq_builder.publish_follow_target({}, "p_1", { x = 1 })
    _assert_eq(ok, false, "missing follow state should be rejected")

    ok = seq_builder.publish_follow_target({ state = {} }, nil, { x = 1 })
    _assert_eq(ok, false, "missing player id should be rejected")

    ok = seq_builder.publish_follow_target({ state = {} }, "p_1", nil)
    _assert_eq(ok, false, "missing position should be rejected")
  end)

  it("test_publish_follow_target_passes_seq_and_source", function()
    -- 杀 L132 _follow_seq 的 or->and 与 L141 _follow_seq()->nil:
    -- anim_ctx.seq 必须透传到 follow opts。
    local captured = nil
    _with_patches({
      {
        target = runtime_state,
        key = "set_follow_target_position",
        value = function(state, player_id, position, opts)
          captured = { state, player_id, position, opts }
          return true
        end,
      },
    }, function()
      local ok = seq_builder.publish_follow_target(
        { state = { marker = 1 }, seq = "seq_7" },
        "p_1",
        { x = 2 },
        "source_a"
      )
      _assert_eq(ok, true, "valid follow args should publish")
    end)

    _assert_eq(captured ~= nil, true, "set_follow_target_position should be reached")
    _assert_eq(captured[1].marker, 1, "state should be the anim_ctx state")
    _assert_eq(captured[2], "p_1", "player id should pass through")
    _assert_eq(captured[3].x, 2, "position should pass through")
    _assert_eq(captured[4].seq, "seq_7", "follow seq should come from anim_ctx")
    _assert_eq(captured[4].source, "source_a", "follow source should pass through")
  end)

end)
describe("TestMoveAnimSequenceBuilderDirectionBoundary", function()

  it("test_resolves_a_forward_direction_for_single_step", function()
    -- 杀 L65 steps>0 的 0->1:steps==1 是合法正步数,不得被 >1 误判成无方向。
    local dir = seq_builder.resolve_direction({ steps = 1 })
    luassert.truthy(dir ~= nil, "single positive step should resolve to a direction")
    _assert_eq(dir.z, -1, "single positive step should face the left vector")
  end)
end)
