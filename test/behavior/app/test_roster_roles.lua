---@diagnostic disable: missing-fields
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local roster_roles = require("src.app.roster_roles")
local support = require("test.support.shared_support")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_assets = require("src.config.runtime_assets")
local logger = require("src.foundation.log")

-- roster_roles' only host couplings are runtime_ports.resolve_roles and
-- GameAPI.random_int; synthetic fill is driven by runtime_assets. Stub all three
-- deterministically (random_int -> min keeps the unit-key pool in order) so the
-- roster-building branches are observable, then restore the clean baseline.
local function _configure_assets()
  runtime_assets.configure_for_tests({
    refs = {
      images = {
        AI2 = "AVATAR_2",
        AI3 = "AVATAR_3",
        AI4 = "AVATAR_4",
        Empty = "EMPTY_IMG",
      },
      synthetic_ai = {
        names = { [2] = "乙", [3] = "丙", [4] = "丁" },
        unit_keys = { "U1", "U2", "U3", "U4" },
      },
    },
    constants = {},
    skins = {},
    startup_item_ids = {},
  })
end

local function _role(id, name)
  return {
    get_roleid = function() return id end,
    get_name = function() return name end,
  }
end

-- Run `fn` with resolve_roles stubbed to `roles_source` (a value or a function),
-- GameAPI.random_int deterministic, and logger calls captured. `calls` counts how
-- often the resolver ran so the first-resolve-vs-retry branch stays observable.
local function _with_roles(roles_source, fn)
  local saved_gameapi = _G.GameAPI
  local saved_warn, saved_info = logger.warn, logger.info
  local logs = { warn = 0, info = 0, resolve_calls = 0, warn_args = {}, info_args = {} }
  logger.warn = function(...)
    logs.warn = logs.warn + 1
    logs.warn_args[#logs.warn_args + 1] = { ... }
  end
  logger.info = function(...)
    logs.info = logs.info + 1
    logs.info_args[#logs.info_args + 1] = { ... }
  end
  _G.GameAPI = { random_int = function(min, _) return min end }
  _configure_assets()
  local base = type(roles_source) == "function" and roles_source or function() return roles_source end
  runtime_ports.configure({
    resolve_roles = function()
      logs.resolve_calls = logs.resolve_calls + 1
      return base()
    end,
  })
  local ok, err = pcall(fn, logs)
  runtime_ports.reset_for_tests()
  runtime_assets.reset_for_tests()
  _G.GameAPI = saved_gameapi
  logger.warn, logger.info = saved_warn, saved_info
  luassert.truthy(ok, err)
end

local function _count_synthetic(roster)
  local n = 0
  for _, entry in ipairs(roster) do
    if entry.synthetic == true then
      n = n + 1
    end
  end
  return n
end

describe("TestRosterRolesBuildStartupRoster", function()
  after_each(function()
    -- _with_roles 拆了共享端口基线必须装回。
    support.restore_runtime_services()
  end)

local function _test_seats_exactly_the_real_roles_when_their_count_matches_the_cap()
  _with_roles({ _role(101, "甲"), _role(102, "乙"), _role(103, "丙"), _role(104, "丁") }, function(logs)
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(#roster == 4, "should seat four roles, got " .. tostring(#roster))
    luassert.truthy(_count_synthetic(roster) == 0, "a full real roster needs no synthetic fill")
    luassert.truthy(roster[1].role_id == 101, "first seat keeps the resolved role id")
    luassert.truthy(roster[1].name == "甲", "first seat keeps the resolved role name")
    luassert.truthy(logs.warn == 0, "an exactly-full roster must not warn about truncation")
    luassert.truthy(logs.resolve_calls == 1, "a successful first resolve must not trigger a retry")
  end)
end

local function _test_fills_the_remaining_seats_with_synthetic_roles_in_pool_order()
  _with_roles({ _role(101, "甲") }, function(logs)
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(#roster == 4, "should fill up to the cap, got " .. tostring(#roster))
    luassert.truthy(logs.resolve_calls == 1, "a non-empty first resolve must not retry")
    luassert.truthy(_count_synthetic(roster) == 3, "three seats should be synthetic")
    luassert.truthy(roster[1].role_id == 101, "the single real role keeps its seat")
    luassert.truthy(roster[2].synthetic == true and roster[2].role_id == -2, "second seat is synthetic slot -2")
    luassert.truthy(roster[2].unit_key == "U1", "synthetic seats consume the unit-key pool in order")
    luassert.truthy(roster[3].unit_key == "U2", "third synthetic seat takes the next pool key")
    luassert.truthy(roster[4].role_id == -4, "fourth synthetic seat is slot -4")
    luassert.truthy(roster[2].avatar_image_key == "AVATAR_2", "synthetic avatar resolves from the AI image ref")
  end)
end

local function _test_truncates_real_roles_past_the_cap_and_warns()
  _with_roles({
    _role(101), _role(102), _role(103), _role(104), _role(105), _role(106),
  }, function(logs)
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(#roster == 4, "roster must clamp to the cap, got " .. tostring(#roster))
    luassert.truthy(_count_synthetic(roster) == 0, "an over-full real roster needs no synthetic fill")
    luassert.truthy(logs.warn == 1, "truncation should warn exactly once")
  end)
end

local function _test_skips_roles_without_a_resolvable_id_and_backfills_with_synthetic_seats()
  _with_roles({ _role(101, "甲"), _role(nil, "无效"), _role(103, "丙") }, function()
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(roster[1].role_id == 101, "first valid role keeps its seat")
    luassert.truthy(roster[2].role_id == 103, "the id-less role is skipped, not seated")
    luassert.truthy(_count_synthetic(roster) == 2, "the two empty seats are filled synthetically")
  end)
end

local function _test_drops_empty_role_names_to_nil()
  _with_roles({ _role(101, "") }, function()
    local roster = roster_roles.build_startup_roster(1)
    luassert.truthy(#roster == 1, "cap of one seats a single role")
    luassert.truthy(roster[1].role_id == 101, "the real role is seated")
    luassert.truthy(roster[1].name == nil, "an empty role name resolves to nil")
  end)
end

local function _test_retries_the_role_resolver_once_and_logs_the_recovery()
  local attempts = 0
  _with_roles(function()
    attempts = attempts + 1
    if attempts == 1 then
      return {}
    end
    return { _role(201, "甲"), _role(202, "乙") }
  end, function(logs)
    local roster = roster_roles.build_startup_roster(4)
    -- lint-allow: call-count 角色解析器经 _with_roles 注入,空结果恰重试一次是对外契约
    luassert.truthy(attempts == 2, "an empty first resolve should trigger exactly one retry")
    luassert.truthy(roster[1].role_id == 201, "the retried roles are seated")
    luassert.truthy(logs.info >= 1, "a successful retry should log the recovery")
    luassert.truthy(_count_synthetic(roster) == 2, "remaining seats are filled synthetically")
  end)
end

local function _test_seats_an_all_synthetic_roster_when_no_real_roles_resolve()
  _with_roles({}, function()
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(#roster == 4, "the cap is filled entirely with synthetic seats")
    luassert.truthy(_count_synthetic(roster) == 4, "every seat is synthetic")
    luassert.truthy(roster[1].role_id == -1, "synthetic seats start at slot -1")
  end)
end

local function _test_seats_every_real_role_with_no_synthetic_fill_when_the_cap_is_unset()
  _with_roles({ _role(101, "甲"), _role(102, "乙") }, function()
    local roster = roster_roles.build_startup_roster(nil)
    luassert.truthy(#roster == 2, "an unset cap seats exactly the resolved roles")
    luassert.truthy(_count_synthetic(roster) == 0, "an unset cap performs no synthetic backfill")
  end)
end

local function _test_skips_roles_missing_a_get_roleid_accessor_entirely()
  _with_roles({ { get_name = function() return "无效" end }, _role(103, "丙") }, function()
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(roster[1].role_id == 103, "the accessor-less role is skipped, not seated")
    luassert.truthy(_count_synthetic(roster) == 3, "the empty seats are backfilled synthetically")
  end)
end

local function _test_skips_roles_whose_id_accessor_raises()
  _with_roles({ { get_roleid = function() error("boom") end }, _role(103, "丙") }, function()
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(roster[1].role_id == 103, "a raising id accessor is skipped, not seated")
    luassert.truthy(_count_synthetic(roster) == 3, "the empty seats are backfilled synthetically")
  end)
end

-- 批3 击杀：截断告警的参数面（tag/文案/两个 tostring 展开）——只数 warn 次数
-- 杀不掉 L120-124，必须 pin 住告警实际发出的四个实参。
local function _test_truncation_warn_carries_expected_args()
  _with_roles({
    _role(101), _role(102), _role(103), _role(104), _role(105), _role(106),
  }, function(logs)
    roster_roles.build_startup_roster(4)
    luassert.truthy(#logs.warn_args == 1, "truncation should warn exactly once")
    luassert.truthy(logs.warn_args[1][1] == "[Eggy]", "truncation warn should carry the Eggy tag")
    luassert.truthy(logs.warn_args[1][2] == "角色数量超过上限，已截断:",
      "truncation warn should carry the truncation notice")
    luassert.truthy(logs.warn_args[1][3] == "6", "truncation warn should expand the resolved role count")
    luassert.truthy(logs.warn_args[1][4] == "->", "truncation warn should keep the arrow separator")
    luassert.truthy(logs.warn_args[1][5] == "4", "truncation warn should expand the cap")
  end)
end

-- 批3 击杀：二次拉取恢复日志的参数面（tag/文案/数量展开），pin 住 L15 三处。
local function _test_retry_recovery_logs_expected_args()
  local attempts = 0
  _with_roles(function()
    attempts = attempts + 1
    if attempts == 1 then
      return {}
    end
    return { _role(201, "甲"), _role(202, "乙") }
  end, function(logs)
    roster_roles.build_startup_roster(4)
    luassert.truthy(#logs.info_args == 1, "a successful retry should log exactly once")
    luassert.truthy(logs.info_args[1][1] == "[Eggy]", "retry log should carry the Eggy tag")
    luassert.truthy(logs.info_args[1][2] == "角色列表二次拉取成功，角色数量:",
      "retry log should carry the recovery notice")
    luassert.truthy(logs.info_args[1][3] == "2", "retry log should expand the retried role count")
  end)
end

-- 批3 击杀 L14(>=)：二次结果为空表时不算「拉取成功」，不能发恢复日志。
local function _test_empty_retry_result_is_not_treated_as_recovery()
  _with_roles({}, function(logs)
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(logs.info == 0, "an empty retry result must not log a recovery")
    luassert.truthy(logs.resolve_calls == 2, "an empty first resolve should still retry once")
    luassert.truthy(_count_synthetic(roster) == 4, "an empty retry leaves the cap fully synthetic")
  end)
end

-- 批3 击杀 L14(and→or)：解析器返回非表（带长度的字符串）时不能当成功处理。
local function _test_non_table_resolver_result_is_rejected()
  _with_roles("abc", function(logs)
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(logs.info == 0, "a non-table resolver result must not log a recovery")
    luassert.truthy(_count_synthetic(roster) == 4, "a rejected resolver result leaves the cap fully synthetic")
  end)
end

-- 批3 击杀 L48(0→1)：恰好缺一座（missing_count=1）时合成角色必须拿到真实
-- unit_key（0→1 变异会让 count=1 提前返回空选集，槽位 unit_key 变 nil）。
local function _test_single_missing_seat_keeps_a_real_unit_key()
  _with_roles({ _role(101, "甲"), _role(102, "乙"), _role(103, "丙") }, function()
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(#roster == 4, "cap of four with three real roles leaves one seat")
    luassert.truthy(_count_synthetic(roster) == 1, "exactly one seat should be synthetic")
    luassert.truthy(roster[4].synthetic == true and roster[4].role_id == -4,
      "the missing seat is the synthetic slot -4")
    luassert.truthy(roster[4].unit_key == "U1", "a single synthetic seat keeps the first pool key")
  end)
end

-- 批3 击杀 L60(and→or)：角色列表里的 false 脏条目必须被跳过而不是触发索引崩溃
--（ipairs 会在 nil 处停住，用 false 才能让后续角色仍被遍历）。
local function _test_dirty_false_entries_in_roles_list_are_skipped()
  _with_roles({ false, _role(101, "甲") }, function()
    local roster = roster_roles.build_startup_roster(4)
    luassert.truthy(roster[1].role_id == 101, "the real role after a false entry is still seated")
    luassert.truthy(_count_synthetic(roster) == 3, "the remaining seats are backfilled synthetically")
  end)
end

local function _test_drops_the_name_to_nil_when_the_name_accessor_raises()
  _with_roles({ { get_roleid = function() return 101 end, get_name = function() error("boom") end } }, function()
    local roster = roster_roles.build_startup_roster(1)
    luassert.truthy(roster[1].role_id == 101, "the role is still seated despite the name failure")
    luassert.truthy(roster[1].name == nil, "a raising name accessor resolves to nil, not the error")
  end)
end

-- 帧同步下 GameAPI.random_int 是全局共享随机流:开局只为真正空缺的席位抽
-- unit_key,多抽会平移后续骰子等随机结果。
local function _with_recorded_draws(roles, max_players)
  local draws = {}
  _with_roles(roles, function()
    _G.GameAPI.random_int = function(min, max)
      draws[#draws + 1] = { min, max }
      return min
    end
    roster_roles.build_startup_roster(max_players)
  end)
  return draws
end

local function _test_draws_random_unit_keys_only_for_the_missing_seats()
  local draws = _with_recorded_draws({ _role(101, "甲") }, 4)
  luassert.same({ { 1, 4 }, { 2, 4 }, { 3, 4 } }, draws)
end

local function _test_unset_cap_draws_nothing_from_the_random_stream()
  local draws = _with_recorded_draws({ _role(101, "甲"), _role(102, "乙") }, nil)
  luassert.same({}, draws)
end

it("test_seats_exactly_the_real_roles_when_their_count_matches_the_cap", _test_seats_exactly_the_real_roles_when_their_count_matches_the_cap)
it("test_fills_the_remaining_seats_with_synthetic_roles_in_pool_order", _test_fills_the_remaining_seats_with_synthetic_roles_in_pool_order)
it("test_truncates_real_roles_past_the_cap_and_warns", _test_truncates_real_roles_past_the_cap_and_warns)
it("test_skips_roles_without_a_resolvable_id_and_backfills_with_synthetic_seats", _test_skips_roles_without_a_resolvable_id_and_backfills_with_synthetic_seats)
it("test_drops_empty_role_names_to_nil", _test_drops_empty_role_names_to_nil)
it("test_retries_the_role_resolver_once_and_logs_the_recovery", _test_retries_the_role_resolver_once_and_logs_the_recovery)
it("test_seats_an_all_synthetic_roster_when_no_real_roles_resolve", _test_seats_an_all_synthetic_roster_when_no_real_roles_resolve)
it("test_seats_every_real_role_with_no_synthetic_fill_when_the_cap_is_unset", _test_seats_every_real_role_with_no_synthetic_fill_when_the_cap_is_unset)
it("test_skips_roles_missing_a_get_roleid_accessor_entirely", _test_skips_roles_missing_a_get_roleid_accessor_entirely)
it("test_skips_roles_whose_id_accessor_raises", _test_skips_roles_whose_id_accessor_raises)
it("test_truncation_warn_carries_expected_args", _test_truncation_warn_carries_expected_args)
it("test_retry_recovery_logs_expected_args", _test_retry_recovery_logs_expected_args)
it("test_empty_retry_result_is_not_treated_as_recovery", _test_empty_retry_result_is_not_treated_as_recovery)
it("test_non_table_resolver_result_is_rejected", _test_non_table_resolver_result_is_rejected)
it("test_single_missing_seat_keeps_a_real_unit_key", _test_single_missing_seat_keeps_a_real_unit_key)
it("test_dirty_false_entries_in_roles_list_are_skipped", _test_dirty_false_entries_in_roles_list_are_skipped)
it("test_drops_the_name_to_nil_when_the_name_accessor_raises", _test_drops_the_name_to_nil_when_the_name_accessor_raises)
it("test_draws_random_unit_keys_only_for_the_missing_seats", _test_draws_random_unit_keys_only_for_the_missing_seats)
it("test_unset_cap_draws_nothing_from_the_random_stream", _test_unset_cap_draws_nothing_from_the_random_stream)
end)

describe("TestRosterRolesBuildStartupAiMap", function()

local function _test_marks_only_synthetic_role_ids()
  local ai = roster_roles.build_startup_ai_map({
    { role_id = 1 },
    { role_id = -2, synthetic = true },
    { role_id = -3, synthetic = true },
  })
  luassert.truthy(ai ~= nil, "a roster with synthetic seats yields an ai map")
  luassert.truthy(ai[-2] == true and ai[-3] == true, "synthetic seats are marked ai")
  luassert.truthy(ai[1] == nil, "real seats are never marked ai")
end

local function _test_returns_nil_for_an_all_real_or_empty_roster()
  luassert.truthy(roster_roles.build_startup_ai_map({ { role_id = 1 }, { role_id = 2 } }) == nil,
    "an all-real roster has no ai map")
  luassert.truthy(roster_roles.build_startup_ai_map({}) == nil, "an empty roster has no ai map")
  luassert.truthy(roster_roles.build_startup_ai_map(nil) == nil, "a nil roster has no ai map")
end

it("test_marks_only_synthetic_role_ids", _test_marks_only_synthetic_role_ids)
it("test_returns_nil_for_an_all_real_or_empty_roster", _test_returns_nil_for_an_all_real_or_empty_roster)
end)

describe("TestRosterRolesBuildSyntheticPlayerSpecs", function()

local function _test_emits_one_spec_per_synthetic_seat_preserving_fields_and_order()
  local specs = roster_roles.build_synthetic_player_specs({
    { role_id = 1, name = "甲" },
    { role_id = -2, synthetic = true, name = "乙", unit_key = "U1", avatar_image_key = "A2" },
    { role_id = -3, synthetic = true, name = "丙", unit_key = "U2", avatar_image_key = "A3" },
  })
  luassert.truthy(#specs == 2, "only synthetic seats produce specs, got " .. tostring(#specs))
  luassert.truthy(specs[1].player_id == -2, "spec carries the synthetic role id as player_id")
  luassert.truthy(specs[1].name == "乙" and specs[1].unit_key == "U1" and specs[1].avatar_image_key == "A2",
    "spec preserves the synthetic seat fields")
  luassert.truthy(specs[2].player_id == -3, "specs preserve roster order")
end

local function _test_returns_an_empty_list_when_there_are_no_synthetic_seats()
  local specs = roster_roles.build_synthetic_player_specs({ { role_id = 1 } })
  luassert.truthy(#specs == 0, "a real-only roster yields no synthetic specs")
end

it("test_emits_one_spec_per_synthetic_seat_preserving_fields_and_order", _test_emits_one_spec_per_synthetic_seat_preserving_fields_and_order)
it("test_returns_an_empty_list_when_there_are_no_synthetic_seats", _test_returns_an_empty_list_when_there_are_no_synthetic_seats)
end)

-- ===== 迁自 test/property/test_roster_seating.lua（#190）=====
describe("TestRosterRolesSeatingClampFill", function()

  local property = require("test.support.property")
  local roster = require("src.app.roster")
  local balance = require("src.player.actions.balance")

  local SEATS = 4

  -- Mirror the real-startup seam used by the legacy acceptance setup: roster's only host
  -- couplings are runtime_ports.resolve_roles and GameAPI.random_int. Stub both for a
  -- synchronous release build (which bypasses profile bootstrap), then restore the
  -- clean baseline so cases never leak into each other.
  local function _mock_roles(count)
    local roles = {}
    for i = 1, count do
      local role_id = 100 + i
      local attrs = {}
      local role = {}
      role.get_roleid = function() return role_id end
      role.get_name = function() return "真人" .. tostring(i) end
      role.get_attr_raw_fixed = function(first, second)
        local attr_id = first == role and second or first
        return attrs[attr_id]
      end
      role.set_attr_raw_fixed = function(first, second, third)
        local attr_id = first == role and second or first
        local value = first == role and third or second
        attrs[attr_id] = value
        return attr_id == balance.COIN_COUNT_ATTR_ID
      end
      roles[i] = role
    end
    return roles
  end

  local function _build_with_signups(signup_count, factory_opts)
    local saved_gameapi = _G.GameAPI
    _G.GameAPI = { random_int = function(min, _) return min end }
    runtime_ports.configure({
      resolve_roles = function() return _mock_roles(signup_count) end,
    })
    local ok, result = pcall(function()
      return roster.build_game_factory({}, factory_opts)()
    end)
    runtime_ports.reset_for_tests()
    _G.GameAPI = saved_gameapi
    luassert.truthy(ok, "roster build failed for signup_count=" .. tostring(signup_count) .. ": " .. tostring(result))
    return result
  end

  local function _count_ai(game)
    local ai = 0
    for _, player in ipairs(game.players) do
      if player.is_ai == true then
        ai = ai + 1
      end
    end
    return ai
  end

  -- 0 -> all AI, 1..3 -> mixed, 4 -> boundary all-real, 5..8 -> real roles truncated.
  after_each(function()
    support.restore_runtime_services()
  end)

  it("test_always_seats_exactly_four_roles_filling_the_ai_remainder_and_truncating_overflow", function()
    property.check_int_range(0, 8, function(signup_count)
      local game = _build_with_signups(signup_count)
      local total = #game.players
      local ai = _count_ai(game)
      local real = total - ai
      local seated_real = math.min(signup_count, SEATS)

      luassert.truthy(total == SEATS,
        "expected " .. SEATS .. " seated roles for signup=" .. signup_count .. ", got " .. tostring(total))
      luassert.truthy(real == seated_real,
        "expected " .. seated_real .. " real roles for signup=" .. signup_count .. ", got " .. tostring(real))
      luassert.truthy(ai == SEATS - seated_real,
        "expected " .. (SEATS - seated_real) .. " AI roles for signup=" .. signup_count .. ", got " .. tostring(ai))
      luassert.truthy(real + ai == SEATS,
        "real + AI roles must conserve to " .. SEATS .. " for signup=" .. signup_count)
    end)
  end)

  local function _delegated_flags(game)
    local control = require("src.player.control")
    local flags = {}
    for index, player in ipairs(game.players) do
      flags[index] = control.is_delegated(player)
    end
    return flags
  end

  it("test_real_players_start_undelegated_unless_auto_all_is_explicitly_true", function()
    luassert.same({ false, false, false, false }, _delegated_flags(_build_with_signups(SEATS)))
    luassert.same({ false, false, false, false }, _delegated_flags(_build_with_signups(SEATS, { auto_all = "yes" })))
  end)

  it("test_auto_all_delegates_every_real_player", function()
    luassert.same({ true, true, true, true }, _delegated_flags(_build_with_signups(SEATS, { auto_all = true })))
  end)
end)
