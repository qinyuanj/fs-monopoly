-- Host sound bridge guards: success/missing-host/invalid-rate/throwing-host
-- paths for src.host.sound. These boundary branches are only reachable by
-- driving the module directly with a patched host API surface.
local support = require("test.support.shared_support")
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end
local _with_patches = support.with_patches
local sound = require("src.host.sound")
local logger = require("src.foundation.log")
local runtime_constants = require("src.config.gameplay.runtime_constants")

describe("TestSound", function()

local function _test_bind_sfx_to_unit_reports_success_and_a_missing_host_function()
  local calls = 0
  local unit = {}

  _with_patches({
    { key = "GlobalAPI", value = {
      bind_sfx_to_unit = function(sfx_id, target_unit, socket_name, pos, bind_type)
        calls = calls + 1
        _assert_eq(sfx_id, 7, "sfx id should pass through")
        _assert_eq(target_unit, unit, "unit should pass through")
        _assert_eq(socket_name, "body", "socket should pass through")
        _assert_eq(pos.x, 1, "position should pass through")
        _assert_eq(bind_type, "follow", "bind type should pass through")
      end,
    } },
  }, function()
    _assert_eq(sound.bind_sfx_to_unit(7, unit, "body", { x = 1 }, "follow"), true,
      "bind should return true when host call succeeds")
  end)

  _assert_eq(calls, 1, "host bind should be called once")
  _with_patches({
    { key = "GlobalAPI", value = {} },
  }, function()
    _assert_eq(sound.bind_sfx_to_unit(7, unit), false, "missing host bind should return false")
  end)
end

-- play_sfx_by_key 的 scale 校验:数组形态向量(仅有 index 分量)判定为无效并跳过。
local function _test_play_sfx_by_key_rejects_array_vector_scale()
  local result = sound.play_sfx_by_key(100, { x = 0 }, nil, { 1, 2, 3 }, 0.1, 1.0, true, { cue_name = "cue" })
  _assert_eq(result, nil, "array vector scale should be rejected")
end

local function _test_bind_sfx_to_unit_rejects_missing_sfx_id_or_unit()
  _assert_eq(sound.bind_sfx_to_unit(nil, {}), false,
    "missing sfx id should return false before touching the host")
  _assert_eq(sound.bind_sfx_to_unit(7, nil), false,
    "missing unit should return false before touching the host")
end

local function _test_play_sfx_by_key_validates_rate_and_routes_a_valid_host_call()
  local calls = {}

  _with_patches({
    { key = "GameAPI", value = {
      play_sfx_by_key = function(sfx_key, pos, rot, scale, duration, rate, with_sound)
        calls[#calls + 1] = {
          sfx_key = sfx_key,
          pos = pos,
          rot = rot,
          scale = scale,
          duration = duration,
          rate = rate,
          with_sound = with_sound,
        }
        return 77
      end,
    } },
  }, function()
    _assert_eq(sound.play_sfx_by_key(100, nil, nil, 2.0, nil, nil, true), 77,
      "valid sfx should return host id")
    _assert_eq(sound.play_sfx_by_key(101, nil, nil, 2.0, nil, "bad", false), 77,
      "invalid rate input should fall back to default rate")
  end)

  _assert_eq(#calls, 2, "valid sfx calls should reach host")
  _assert_eq(calls[1].sfx_key, 100, "sfx key should be integer")
  _assert_eq(calls[1].scale, 2.0, "scale should pass through")
  _assert_eq(calls[1].duration, 1.0, "duration should use default")
  _assert_eq(calls[1].rate, 1.0, "rate should use default")
  _assert_eq(calls[1].with_sound, true, "with_sound should pass true")
  _assert_eq(calls[2].rate, 1.0, "invalid rate input should use default")
end

local function _test_play_sfx_by_key_returns_nil_when_the_host_call_is_missing_or_errors()
  _with_patches({
    { key = "GameAPI", value = {} },
  }, function()
    _assert_eq(sound.play_sfx_by_key(100, nil, nil, 2.0), nil,
      "missing GameAPI.play_sfx_by_key should skip and return nil")
  end)

  local raised = 0
  local warned = 0
  _with_patches({
    { key = "GameAPI", value = {
      play_sfx_by_key = function()
        raised = raised + 1
        error("host sfx boom")
      end,
    } },
    { target = logger, key = "warn", value = function()
      warned = warned + 1
    end },
  }, function()
    _assert_eq(sound.play_sfx_by_key(100, nil, nil, 2.0), nil,
      "a throwing host call should be swallowed and return nil")
  end)

  _assert_eq(raised, 1, "the host sfx call should have been attempted once")
  _assert_eq(warned, 1, "a swallowed host error should emit a skip warning")
end

-- ── _is_vector_like edge cases ────────────────────────────────────
-- exercised through play_sfx_by_key(_resolve_sfx_params → _scale_invalid →
-- _is_vector_like).

local function _test_play_sfx_by_key_rejects_table_with_only_x_component()
  _assert_eq(sound.play_sfx_by_key(100, nil, nil, { x = 5 }, 0.1, 1.0, true, { cue_name = "cue" }), nil,
    "table with only x component (named vector) should be rejected as scale")
end

local function _test_play_sfx_by_key_rejects_table_with_only_first_indexed_component()
  _assert_eq(sound.play_sfx_by_key(100, nil, nil, { 7 }, 0.1, 1.0, true, { cue_name = "cue" }), nil,
    "table with only [1] (indexed vector) should be rejected as scale")
end

local function _test_play_sfx_by_key_accepts_plain_number_two_point_zero_as_scale()
  local calls = {}
  _with_patches({
    { key = "GameAPI", value = {
      play_sfx_by_key = function(sfx_key, pos, rot, scale)
        calls[#calls + 1] = scale
        return 88
      end,
    } },
  }, function()
    local result = sound.play_sfx_by_key(100, nil, nil, 2.0, 0.1, 1.0, true)
    _assert_eq(result, 88, "numeric scale 2.0 should be accepted")
    _assert_eq(calls[1], 2.0, "numeric scale should pass through")
  end)
end

-- ── _resolve_rotation: explicit rot provided ──────────────────────

local function _test_play_sfx_by_key_passes_explicit_rotation_to_host()
  local calls = {}
  local rot = { x = 0, y = 0, z = 1 }
  _with_patches({
    { key = "GameAPI", value = {
      play_sfx_by_key = function(sfx_key, pos, passed_rot)
        calls[#calls + 1] = { sfx_key = sfx_key, pos = pos, rot = passed_rot }
        return 11
      end,
    } },
  }, function()
    sound.play_sfx_by_key(100, nil, rot, 1.0, nil, nil, true)
  end)
  _assert_eq(calls[1].rot, rot, "explicit rotation should pass through to host")
end

-- ── _with_sound_flag: with_sound=false ────────────────────────────

local function _test_play_sfx_by_key_passes_explicit_with_sound_false_to_host()
  local calls = {}
  _with_patches({
    { key = "GameAPI", value = {
      play_sfx_by_key = function(sfx_key, pos, rot, scale, duration, rate, with_sound)
        calls[#calls + 1] = with_sound
        return 55
      end,
    } },
  }, function()
    sound.play_sfx_by_key(100, nil, nil, 1.0, nil, nil, false)
  end)
  _assert_eq(calls[1], false, "explicit with_sound=false should reach host")
end

-- ── _invalid_sfx_key: boundary sfx_key=1 ──────────────────────────

local function _test_play_sfx_by_key_accepts_sfx_key_of_one_as_valid()
  local calls = {}
  _with_patches({
    { key = "GameAPI", value = {
      play_sfx_by_key = function(sfx_key)
        calls[#calls + 1] = sfx_key
        return 22
      end,
    } },
  }, function()
    local result = sound.play_sfx_by_key(1, nil, nil, 1.0, nil, nil, true)
    _assert_eq(result, 22, "sfx_key=1 should be valid")
    _assert_eq(calls[1], 1, "host should receive sfx_key=1")
  end)
end

-- ── play_3d_sound: valid sound_id=1 boundary ──────────────────────

local function _test_play_3d_sound_accepts_sound_id_of_one_as_valid()
  local calls = {}
  _with_patches({
    { key = "GameAPI", value = {
      play_3d_sound = function(pos, sid)
        calls[#calls + 1] = { pos = pos, sid = sid }
        return 33
      end,
    } },
  }, function()
    local result = sound.play_3d_sound({ x = 0, y = 0, z = 0 }, 1)
    _assert_eq(result, 33, "sound_id=1 should be valid")
    _assert_eq(calls[1].sid, 1, "host should receive sound_id=1")
  end)
end

-- ── play_3d_sound: game_api exists but no play_3d_sound function ──

local function _test_play_3d_sound_returns_nil_when_game_api_missing_play_3d_sound()
  _with_patches({
    { key = "GameAPI", value = { get_timestamp = function() return 0 end } },
  }, function()
    _assert_eq(sound.play_3d_sound({ x = 0 }, 100), nil,
      "missing play_3d_sound function should return nil")
  end)
end

-- ── play_3d_sound: host call raises ───────────────────────────────

local function _test_play_3d_sound_returns_nil_when_host_call_raises()
  local warned = 0
  _with_patches({
    { key = "GameAPI", value = {
      play_3d_sound = function()
        error("3d sound boom")
      end,
    } },
    { target = logger, key = "warn", value = function() warned = warned + 1 end },
  }, function()
    _assert_eq(sound.play_3d_sound({ x = 0 }, 100), nil,
      "throwing host 3d sound call should return nil")
  end)
  _assert_eq(warned, 1, "swallowed 3d sound error should warn")
end

-- ── bind_sfx_to_unit: GlobalAPI present but bind_sfx_to_unit not function ──

local function _test_bind_sfx_to_unit_returns_false_when_bind_is_not_a_function()
  _with_patches({
    { key = "GlobalAPI", value = { bind_sfx_to_unit = "not-a-function" } },
  }, function()
    _assert_eq(sound.bind_sfx_to_unit(7, {}), false,
      "non-function bind_sfx_to_unit should return false")
  end)
end

-- ── bind_sfx_to_unit: both sfx_id and unit present, host call succeeds ──

local function _test_bind_sfx_to_unit_calls_host_when_both_params_valid()
  local unit = { id = "u1" }
  local captured = {}
  _with_patches({
    { key = "GlobalAPI", value = {
      bind_sfx_to_unit = function(sfx_id, u, socket, pos, bind_type)
        captured = { sfx_id = sfx_id, unit = u, socket = socket, pos = pos, bind_type = bind_type }
      end,
    } },
  }, function()
    _assert_eq(sound.bind_sfx_to_unit(7, unit, nil, nil, nil), true,
      "valid sfx_id and unit should return true")
  end)
  _assert_eq(captured.sfx_id, 7, "sfx_id should pass through")
  _assert_eq(captured.unit, unit, "unit should pass through")
end

-- ── _is_vector_like: 每个分量单独出现都判为向量,非向量表回落默认 scale ──

local function _play_with_host_scale_capture(scale)
  local scales = {}
  local result
  _with_patches({
    { key = "GameAPI", value = {
      play_sfx_by_key = function(_, _, _, passed_scale)
        scales[#scales + 1] = passed_scale
        return 99
      end,
    } },
  }, function()
    result = sound.play_sfx_by_key(100, nil, nil, scale, 0.1, 1.0, true, { cue_name = "cue" })
  end)
  return result, scales
end

local function _test_play_sfx_by_key_rejects_named_vector_scale_with_only_y_or_z()
  local result_y, scales_y = _play_with_host_scale_capture({ y = 5 })
  _assert_eq(result_y, nil, "table with only y component should be rejected as scale")
  _assert_eq(#scales_y, 0, "rejected y-only scale must not reach the host")
  local result_z, scales_z = _play_with_host_scale_capture({ z = 5 })
  _assert_eq(result_z, nil, "table with only z component should be rejected as scale")
  _assert_eq(#scales_z, 0, "rejected z-only scale must not reach the host")
end

local function _test_play_sfx_by_key_rejects_indexed_vector_scale_with_only_second_or_third()
  local result_2, scales_2 = _play_with_host_scale_capture({ [2] = 5 })
  _assert_eq(result_2, nil, "table with only [2] should be rejected as scale")
  _assert_eq(#scales_2, 0, "rejected [2]-only scale must not reach the host")
  local result_3, scales_3 = _play_with_host_scale_capture({ [3] = 5 })
  _assert_eq(result_3, nil, "table with only [3] should be rejected as scale")
  _assert_eq(#scales_3, 0, "rejected [3]-only scale must not reach the host")
end

local function _test_play_sfx_by_key_falls_back_to_default_scale_for_non_vector_table()
  local result, scales = _play_with_host_scale_capture({ w = 5 })
  _assert_eq(result, 99, "a table without vector components is not a vector and should play")
  _assert_eq(scales[1], 1.0, "non-numeric non-vector scale should fall back to 1.0")
end

-- ── _resolve_pos: 显式位置透传,缺省回落 v3_zero ───────────────────

local function _test_play_3d_sound_passes_explicit_pos_and_defaults_missing_pos_to_zero()
  local positions = {}
  local pos = { x = 4, y = 5, z = 6 }
  _with_patches({
    { key = "GameAPI", value = {
      play_3d_sound = function(passed_pos)
        positions[#positions + 1] = passed_pos
        return 1
      end,
    } },
  }, function()
    sound.play_3d_sound(pos, 100)
    sound.play_3d_sound(nil, 100)
  end)
  _assert_eq(positions[1], pos, "explicit position should pass through to host")
  _assert_eq(positions[2], runtime_constants.v3_zero, "missing position should fall back to v3_zero")
end

-- ── 宿主全局缺失:不抛错,返回 nil/false ────────────────────────────

local function _test_play_calls_return_nil_without_raising_when_game_api_is_absent()
  _with_patches({
    { key = "GameAPI", value = nil },
  }, function()
    local ok_sfx, sfx_result = pcall(sound.play_sfx_by_key, 100, nil, nil, 1.0)
    _assert_eq(ok_sfx, true, "absent GameAPI must not raise from play_sfx_by_key")
    _assert_eq(sfx_result, nil, "absent GameAPI should make play_sfx_by_key return nil")
    local ok_3d, sound_result = pcall(sound.play_3d_sound, nil, 100)
    _assert_eq(ok_3d, true, "absent GameAPI must not raise from play_3d_sound")
    _assert_eq(sound_result, nil, "absent GameAPI should make play_3d_sound return nil")
  end)
end

local function _test_bind_sfx_to_unit_returns_false_without_raising_when_global_api_is_absent()
  _with_patches({
    { key = "GlobalAPI", value = nil },
  }, function()
    local ok, result = pcall(sound.bind_sfx_to_unit, 7, {})
    _assert_eq(ok, true, "absent GlobalAPI must not raise")
    _assert_eq(result, false, "absent GlobalAPI should return false")
  end)
end

local function _test_bind_sfx_to_unit_skips_host_when_only_one_of_sfx_id_or_unit_is_missing()
  local bound = {}
  _with_patches({
    { key = "GlobalAPI", value = {
      bind_sfx_to_unit = function(sfx_id, unit)
        bound[#bound + 1] = { sfx_id = sfx_id, unit = unit }
      end,
    } },
  }, function()
    _assert_eq(sound.bind_sfx_to_unit(nil, {}), false, "missing sfx id should return false with a live host")
    _assert_eq(sound.bind_sfx_to_unit(7, nil), false, "missing unit should return false with a live host")
  end)
  _assert_eq(#bound, 0, "host bind must not receive a call with a missing sfx id or unit")
end


it("test_bind_sfx_to_unit_reports_success_and_a_missing_host_function", _test_bind_sfx_to_unit_reports_success_and_a_missing_host_function)
it("test_play_sfx_by_key_rejects_array_vector_scale", _test_play_sfx_by_key_rejects_array_vector_scale)
it("test_bind_sfx_to_unit_rejects_missing_sfx_id_or_unit", _test_bind_sfx_to_unit_rejects_missing_sfx_id_or_unit)
it("test_play_sfx_by_key_validates_rate_and_routes_a_valid_host_call", _test_play_sfx_by_key_validates_rate_and_routes_a_valid_host_call)
it("test_play_sfx_by_key_returns_nil_when_the_host_call_is_missing_or_errors", _test_play_sfx_by_key_returns_nil_when_the_host_call_is_missing_or_errors)
it("test_play_sfx_by_key_rejects_table_with_only_x_component", _test_play_sfx_by_key_rejects_table_with_only_x_component)
it("test_play_sfx_by_key_rejects_table_with_only_first_indexed_component", _test_play_sfx_by_key_rejects_table_with_only_first_indexed_component)
it("test_play_sfx_by_key_accepts_plain_number_two_point_zero_as_scale", _test_play_sfx_by_key_accepts_plain_number_two_point_zero_as_scale)
it("test_play_sfx_by_key_passes_explicit_rotation_to_host", _test_play_sfx_by_key_passes_explicit_rotation_to_host)
it("test_play_sfx_by_key_passes_explicit_with_sound_false_to_host", _test_play_sfx_by_key_passes_explicit_with_sound_false_to_host)
it("test_play_sfx_by_key_accepts_sfx_key_of_one_as_valid", _test_play_sfx_by_key_accepts_sfx_key_of_one_as_valid)
it("test_play_3d_sound_accepts_sound_id_of_one_as_valid", _test_play_3d_sound_accepts_sound_id_of_one_as_valid)
it("test_play_3d_sound_returns_nil_when_game_api_missing_play_3d_sound", _test_play_3d_sound_returns_nil_when_game_api_missing_play_3d_sound)
it("test_play_3d_sound_returns_nil_when_host_call_raises", _test_play_3d_sound_returns_nil_when_host_call_raises)
it("test_bind_sfx_to_unit_returns_false_when_bind_is_not_a_function", _test_bind_sfx_to_unit_returns_false_when_bind_is_not_a_function)
it("test_bind_sfx_to_unit_calls_host_when_both_params_valid", _test_bind_sfx_to_unit_calls_host_when_both_params_valid)
it("test_play_sfx_by_key_rejects_named_vector_scale_with_only_y_or_z", _test_play_sfx_by_key_rejects_named_vector_scale_with_only_y_or_z)
it("test_play_sfx_by_key_rejects_indexed_vector_scale_with_only_second_or_third", _test_play_sfx_by_key_rejects_indexed_vector_scale_with_only_second_or_third)
it("test_play_sfx_by_key_falls_back_to_default_scale_for_non_vector_table", _test_play_sfx_by_key_falls_back_to_default_scale_for_non_vector_table)
it("test_play_3d_sound_passes_explicit_pos_and_defaults_missing_pos_to_zero", _test_play_3d_sound_passes_explicit_pos_and_defaults_missing_pos_to_zero)
it("test_play_calls_return_nil_without_raising_when_game_api_is_absent", _test_play_calls_return_nil_without_raising_when_game_api_is_absent)
it("test_bind_sfx_to_unit_returns_false_without_raising_when_global_api_is_absent", _test_bind_sfx_to_unit_returns_false_without_raising_when_global_api_is_absent)
it("test_bind_sfx_to_unit_skips_host_when_only_one_of_sfx_id_or_unit_is_missing", _test_bind_sfx_to_unit_skips_host_when_only_one_of_sfx_id_or_unit_is_missing)
end)
