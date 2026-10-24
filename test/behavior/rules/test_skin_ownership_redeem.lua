-- #198 / #203 / #204 / ADR 0075:礼包码兑换经皮肤归属模块的 redeem(state, role_id,
-- input_text) 驱动。码表只放哈希条目,用明文输入驱动;观察返回的 { status, granted }、
-- 存档替身里的兑换记录与皮肤归属,以及之后 owns / restore 看到的本局与跨局归属。
-- 宿主存档(Int + Str)与墙钟只在 runtime_ports 边界替身。提示文案归礼包码屏。
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local host_double = require("test.support.skin_ownership_host")
local logger = require("src.foundation.log")
local gift_codes = require("src.config.content.gift_codes")
local skin_ownership = require("src.rules.skin_ownership")

local RECORD_KEY = gift_codes.redeem_record_archive_key
local NAILONG = 5005 -- 奶龙,存档 key 1054
local NAILONG_KEY = 1054
local CAPYBARA = 5006 -- 水豚嘟嘟,存档 key 1053
local CAPYBARA_KEY = 1053
local SPONGEBOB = 5003 -- 海绵宝宝,存档 key 1055
local SPONGEBOB_KEY = 1055

-- code_hash 由外部 sha256sum 对规范化后的明文算出:EGG2026 / BUNDLE / SUMMER /
-- ABCDEFGHJKMN(CLI 生成格式的 12 位码)。
local GROUPED_CODE = "ABCD-EFGH-JKMN"
local CODES = {
  { id = 3, code_hash = "682f05b696b1ca1d9b2818d793b2b352f4128f8ba4fa9db8770cfb279fce1f3f", rewards = { NAILONG } },
  { id = 7, code_hash = "4ed9aa46fbbc9b278dac1aa3507747dcdd361832ce9a97f07ecb412d0a601c58",
    rewards = { NAILONG, CAPYBARA, SPONGEBOB } },
  { id = 9, code_hash = "20281d1b6cf1a97468ec8153ec64a4f14b0675023b6fc2b32a1e0afcdf689298",
    rewards = { CAPYBARA }, expires_at = 1000 },
  { id = 11, code_hash = "f798776cb4d1e5975b47ed94fcc91314bc8d5c6935ff56b33c03b08c52356818", rewards = { SPONGEBOB } },
}

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

local function _install_host(opts)
  local host = host_double.install(opts)
  host.host_opts = host.opts
  return host
end

local function _state()
  return { ui = {} }
end

local function _redeem(state, role_id, input)
  return skin_ownership.redeem(state, role_id, input)
end

local function _with_warns(fn)
  local warns = {}
  support.with_patches({
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
  }, fn, { skip_runtime_context_refresh = true })
  return warns
end

describe("TestSkinOwnershipRedeem", function()
  local original_codes

  before_each(function()
    original_codes = gift_codes.codes
    gift_codes.codes = CODES
  end)

  after_each(function()
    gift_codes.codes = original_codes
    support.restore_runtime_services()
  end)

  it("test_valid_code_grants_skin_records_id_and_survives_reentry", function()
    local host = _install_host()
    local state = _state()

    local result = _redeem(state, 1, "EGG2026")

    _assert_eq(result.status, "granted", "valid code should be granted")
    luassert.same({ NAILONG }, result.granted, "granted list should name the new skin")
    _assert_eq(host.read(1, NAILONG_KEY), 1, "skin ownership should be archived")
    _assert_eq(host.read(1, RECORD_KEY), "3", "record should store only the code id")
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), true, "skin should be owned this session")

    local reentered = _state()
    skin_ownership.restore(reentered, 1)
    _assert_eq(skin_ownership.owns(reentered, 1, NAILONG), true, "skin should be owned after re-entry")
  end)

  it("test_input_ignores_surrounding_spaces_and_letter_case", function()
    _install_host()

    local result = _redeem(_state(), 1, "  egg2026 \t")

    _assert_eq(result.status, "granted", "normalized input should match the code")
  end)

  it("test_grouped_code_redeems_with_or_without_hyphens_case_and_spaces", function()
    for role_id, input in ipairs({ GROUPED_CODE, "abcdefghjkmn", "  abcd - EFGH jkmn\t", "ABCD EFGH-JKMN" }) do
      local host = _install_host()
      local result = _redeem(_state(), role_id, input)
      _assert_eq(result.status, "granted", "input should redeem: [" .. input .. "]")
      luassert.same({ SPONGEBOB }, result.granted, "granted list should name the skin")
      _assert_eq(host.read(role_id, RECORD_KEY), "11", "record should store the code id")
    end
  end)

  -- #203 User Story 27:码表里只有哈希,解包者拿到的任何串都兑不出来。
  it("test_no_text_from_the_code_table_redeems", function()
    local host = _install_host()
    local state = _state()

    for _, entry in ipairs(CODES) do
      for _, input in ipairs({ entry.code_hash, tostring(entry.id) }) do
        _assert_eq(_redeem(state, 1, input).status, "invalid_code", "table text should not redeem: " .. input)
      end
    end
    _assert_eq(host.read(1, RECORD_KEY), nil, "nothing should be recorded")
  end)

  it("test_unknown_and_empty_input_are_invalid_code", function()
    local host = _install_host()
    local state = _state()

    for _, input in ipairs({ "NOPE", "", "   ", "---", "ABCD-EFGH-JKMP" }) do
      local result = _redeem(state, 1, input)
      _assert_eq(result.status, "invalid_code", "input should be invalid: [" .. input .. "]")
      luassert.same({}, result.granted, "invalid code should grant nothing")
    end
    _assert_eq(_redeem(state, 1, nil).status, "invalid_code", "missing input should be invalid")
    _assert_eq(host.read(1, RECORD_KEY), nil, "invalid code should not write a record")
  end)

  it("test_code_past_expiry_is_expired", function()
    local host = _install_host({ now = 1001 })

    local result = _redeem(_state(), 1, "SUMMER")

    _assert_eq(result.status, "expired", "code past expires_at should be expired")
    _assert_eq(host.read(1, CAPYBARA_KEY), nil, "expired code should grant nothing")
    _assert_eq(host.read(1, RECORD_KEY), nil, "expired code should not write a record")
  end)

  it("test_code_at_or_before_expiry_or_without_wall_clock_is_redeemable", function()
    for _, now in ipairs({ 1000, 0 }) do
      _install_host({ now = now })
      _assert_eq(_redeem(_state(), 1, "SUMMER").status, "granted", "now=" .. tostring(now) .. " should not expire")
    end
    _install_host({ now = nil })
    _assert_eq(_redeem(_state(), 1, "SUMMER").status, "granted", "missing wall clock should not expire")
  end)

  it("test_same_player_redeeming_twice_is_already_redeemed", function()
    local host = _install_host()
    local state = _state()
    _redeem(state, 1, "EGG2026")

    local again = _redeem(state, 1, "egg2026")

    _assert_eq(again.status, "already_redeemed", "second redemption should be refused")
    _assert_eq(host.read(1, RECORD_KEY), "3", "record should not grow on a refused redemption")
  end)

  it("test_record_from_a_previous_session_blocks_redemption", function()
    _install_host({ seed = { [host_double.seed_key(1, RECORD_KEY)] = "2,3" } })

    _assert_eq(_redeem(_state(), 1, "EGG2026").status, "already_redeemed", "archived record should count")
  end)

  it("test_different_players_each_redeem_the_same_code_once", function()
    local host = _install_host()
    local state = _state()

    _assert_eq(_redeem(state, 1, "EGG2026").status, "granted", "player 1 should redeem")
    _assert_eq(_redeem(state, 2, "EGG2026").status, "granted", "player 2 should redeem the same code")
    _assert_eq(_redeem(state, 2, "EGG2026").status, "already_redeemed", "player 2 should be limited to once")
    _assert_eq(host.read(1, RECORD_KEY), "3", "player 1 record")
    _assert_eq(host.read(2, RECORD_KEY), "3", "player 2 record")
    _assert_eq(skin_ownership.owns(state, 2, NAILONG), true, "player 2 should own the skin")
  end)

  it("test_multi_skin_code_grants_only_unowned_skins_and_appends_record", function()
    local host = _install_host({
      seed = {
        [host_double.seed_key(1, CAPYBARA_KEY)] = 1,
        [host_double.seed_key(1, RECORD_KEY)] = "3",
      },
    })
    local state = _state()

    local result = _redeem(state, 1, "BUNDLE")

    _assert_eq(result.status, "granted", "partially owned bundle should grant the rest")
    luassert.same({ NAILONG, SPONGEBOB }, result.granted, "only unowned skins should be granted")
    _assert_eq(host.read(1, NAILONG_KEY), 1, "nailong archived")
    _assert_eq(host.read(1, SPONGEBOB_KEY), 1, "spongebob archived")
    _assert_eq(host.read(1, RECORD_KEY), "3,7", "record should append the new code id")
  end)

  it("test_all_rewards_owned_still_records_and_reports_all_owned", function()
    local host = _install_host({ seed = { [host_double.seed_key(1, NAILONG_KEY)] = 1 } })
    local state = _state()

    local result = _redeem(state, 1, "EGG2026")

    _assert_eq(result.status, "all_owned", "fully owned rewards should report all_owned")
    luassert.same({}, result.granted, "nothing should be granted")
    _assert_eq(host.read(1, RECORD_KEY), "3", "code should still be recorded as redeemed")
    _assert_eq(_redeem(state, 1, "EGG2026").status, "already_redeemed", "and cannot be redeemed again")
  end)

  it("test_archives_unavailable_refuses_without_reading_or_writing", function()
    local host = _install_host({ enabled = false })
    local state = _state()

    local result = _redeem(state, 1, "EGG2026")

    _assert_eq(result.status, "archive_unavailable", "disabled archives should refuse")
    -- lint-allow: call-count 宿主存档读次数是 ADR 0075「存档不可用不读不写」的边界契约
    _assert_eq(host.reads(), 0, "no archive should be read")
    _assert_eq(host.read(1, RECORD_KEY), nil, "no record should be written")
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), false, "no skin should be granted this session")
  end)

  it("test_unreadable_record_refuses_as_archive_unavailable", function()
    local host = _install_host({ str_unreadable = true })

    local result
    local warns = _with_warns(function()
      result = _redeem(_state(), 1, "EGG2026")
    end)

    _assert_eq(result.status, "archive_unavailable", "unreadable record should refuse rather than overwrite history")
    _assert_eq(host.read(1, NAILONG_KEY), nil, "no skin should be granted")
    _assert_eq(#warns > 0, true, "unreadable record should leave a warn")
  end)

  it("test_record_write_failure_keeps_granted_skin_and_retry_skips_it", function()
    local host = _install_host({ str_write_ok = false })
    local state = _state()

    local result
    local warns = _with_warns(function()
      result = _redeem(state, 1, "EGG2026")
    end)

    _assert_eq(result.status, "write_failed", "unconfirmed record should not count as success")
    luassert.same({ NAILONG }, result.granted, "already granted skin should be reported")
    _assert_eq(host.read(1, NAILONG_KEY), 1, "granted ownership should not be revoked")
    _assert_eq(skin_ownership.owns(state, 1, NAILONG), true, "skin stays owned this session")
    local found = false
    for _, line in ipairs(warns) do
      found = found or (line:find("record", 1, true) ~= nil and line:find("code_id=3", 1, true) ~= nil)
    end
    luassert.truthy(found, "record write failure should leave a warn naming the code")

    host.host_opts.str_write_ok = true
    local retry = _redeem(state, 1, "EGG2026")
    _assert_eq(retry.status, "all_owned", "retry should skip the already granted skin")
    _assert_eq(host.read(1, RECORD_KEY), "3", "retry should land the record")
  end)

  it("test_skin_write_failure_leaves_record_unwritten_for_retry", function()
    local host = _install_host({ int_write_ok = false })
    local state = _state()

    local result
    _with_warns(function()
      result = _redeem(state, 1, "EGG2026")
    end)

    _assert_eq(result.status, "write_failed", "unpersisted skin should not count as success")
    _assert_eq(host.read(1, RECORD_KEY), nil, "record should not be written so the player can retry")

    host.host_opts.int_write_ok = true
    local retry = _redeem(state, 1, "EGG2026")
    _assert_eq(retry.status, "granted", "retry should grant the skin into the archive")
    _assert_eq(host.read(1, NAILONG_KEY), 1, "retry should archive ownership")
  end)

  it("test_retired_ids_in_the_configured_table_are_still_rejected_at_redeem_time", function()
    _install_host()
    local ok, err = pcall(function()
      gift_codes.codes = { { id = 1, code_hash = CODES[1].code_hash, rewards = { NAILONG } } }
      _redeem(_state(), 1, "EGG2026")
    end)
    luassert.is_false(ok, "a table reusing a retired id must not build")
    luassert.truthy(tostring(err):find("gift code id is retired: 1", 1, true), tostring(err))
  end)
end)
