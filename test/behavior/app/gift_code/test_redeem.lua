-- #198 / ADR 0075:礼包码兑换门面。经 redeem(state, role_id, input_text) 输入文本,
-- 观察返回结果、存档替身里的兑换记录与皮肤归属,以及之后 cosmetics 门面看到的
-- 本局与跨局归属。宿主存档(Int + Str)与墙钟只在 runtime_ports 边界替身。
require("test.bootstrap").install_package_paths()
-- busted injects luassert fields on assert.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local logger = require("src.foundation.log")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local transaction = require("src.app.cosmetics.transaction")
local skin_archive = require("src.app.cosmetics.skin_archive")
local redeem = require("src.app.gift_code.redeem")

local RECORD_KEY = require("src.config.content.gift_codes").redeem_record_archive_key
local NAILONG = 5005 -- 奶龙,存档 key 1054
local NAILONG_KEY = 1054
local CAPYBARA = 5006 -- 水豚嘟嘟,存档 key 1053
local CAPYBARA_KEY = 1053
local SPONGEBOB = 5003 -- 海绵宝宝,存档 key 1055
local SPONGEBOB_KEY = 1055

local CODES = {
  { id = 3, code = "EGG2026", rewards = { NAILONG } },
  { id = 7, code = "Bundle", rewards = { NAILONG, CAPYBARA, SPONGEBOB } },
  { id = 9, code = "SUMMER", rewards = { CAPYBARA }, expires_at = 1000 },
}

local function _assert_eq(actual, expected, message)
  luassert.is.equal(expected, actual, message)
end

-- 宿主存档替身:按 role|key 存 Int 与 Str。opts.str_write_ok / int_write_ok = false
-- 模拟宿主不报错但值没落下;opts.str_unreadable 模拟 Str 读档降级为 nil;
-- opts.now 为墙钟秒。
local function _install_host(opts)
  opts = opts or {}
  local store = {}
  for role_key, value in pairs(opts.seed or {}) do
    store[role_key] = value
  end
  local function _key(role_id, key)
    return tostring(role_id) .. "|" .. tostring(key)
  end
  local reads = 0
  runtime_ports.configure({
    archives_enabled = function()
      return opts.enabled ~= false
    end,
    get_archive_int = function(role_id, key)
      reads = reads + 1
      return store[_key(role_id, key)] or 0
    end,
    set_archive_int = function(role_id, key, value)
      if opts.int_write_ok ~= false then
        store[_key(role_id, key)] = value
      end
      return true
    end,
    get_archive_str = function(role_id, key)
      reads = reads + 1
      if opts.str_unreadable then
        return nil
      end
      return store[_key(role_id, key)] or ""
    end,
    set_archive_str = function(role_id, key, value)
      if opts.str_write_ok ~= false then
        store[_key(role_id, key)] = value
      end
      return true
    end,
    wall_now_seconds = function()
      return opts.now
    end,
  })
  return {
    read = function(role_id, key)
      return store[_key(role_id, key)]
    end,
    reads = function()
      return reads
    end,
    host_opts = opts,
  }
end

local function _state()
  return { ui = {} }
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

describe("TestGiftCodeRedeem", function()
  before_each(function()
    transaction.reset_for_tests()
    transaction.configure_archive(skin_archive)
    redeem.configure_codes_for_tests(CODES)
  end)

  after_each(function()
    transaction.reset_for_tests()
    redeem.reset_for_tests()
    support.restore_runtime_services()
  end)

  it("test_valid_code_grants_skin_records_id_and_survives_reentry", function()
    local host = _install_host()
    local state = _state()

    local result = redeem.redeem(state, 1, "EGG2026")

    _assert_eq(result.status, "granted", "valid code should be granted")
    luassert.same({ NAILONG }, result.granted, "granted list should name the new skin")
    luassert.truthy(result.message:find("奶龙", 1, true), "message should name the granted skin: " .. result.message)
    _assert_eq(host.read(1, NAILONG_KEY), 1, "skin ownership should be archived")
    _assert_eq(host.read(1, RECORD_KEY), "3", "record should store only the code id")
    _assert_eq(transaction.owns_product(state, 1, NAILONG), true, "skin should be owned this session")

    local reentered = _state()
    transaction.restore_role(reentered, 1)
    _assert_eq(transaction.owns_product(reentered, 1, NAILONG), true, "skin should be owned after re-entry")
  end)

  it("test_input_ignores_surrounding_spaces_and_letter_case", function()
    _install_host()

    local result = redeem.redeem(_state(), 1, "  egg2026 \t")

    _assert_eq(result.status, "granted", "normalized input should match the code")
  end)

  it("test_unknown_and_empty_input_are_invalid_code", function()
    local host = _install_host()
    local state = _state()

    for _, input in ipairs({ "NOPE", "", "   " }) do
      local result = redeem.redeem(state, 1, input)
      _assert_eq(result.status, "invalid_code", "input should be invalid: [" .. input .. "]")
      _assert_eq(result.message, "兑换码无效", "invalid code message should come from the facade")
      luassert.same({}, result.granted, "invalid code should grant nothing")
    end
    _assert_eq(redeem.redeem(state, 1, nil).status, "invalid_code", "missing input should be invalid")
    _assert_eq(host.read(1, RECORD_KEY), nil, "invalid code should not write a record")
  end)

  it("test_code_past_expiry_is_expired", function()
    local host = _install_host({ now = 1001 })

    local result = redeem.redeem(_state(), 1, "SUMMER")

    _assert_eq(result.status, "expired", "code past expires_at should be expired")
    _assert_eq(result.message, "兑换码已过期", "expired message should come from the facade")
    _assert_eq(host.read(1, CAPYBARA_KEY), nil, "expired code should grant nothing")
    _assert_eq(host.read(1, RECORD_KEY), nil, "expired code should not write a record")
  end)

  it("test_code_at_or_before_expiry_or_without_wall_clock_is_redeemable", function()
    for _, now in ipairs({ 1000, 0 }) do
      _install_host({ now = now })
      _assert_eq(redeem.redeem(_state(), 1, "SUMMER").status, "granted", "now=" .. tostring(now) .. " should not expire")
    end
    _install_host({ now = nil })
    _assert_eq(redeem.redeem(_state(), 1, "SUMMER").status, "granted", "missing wall clock should not expire")
  end)

  it("test_same_player_redeeming_twice_is_already_redeemed", function()
    local host = _install_host()
    local state = _state()
    redeem.redeem(state, 1, "EGG2026")

    local again = redeem.redeem(state, 1, "egg2026")

    _assert_eq(again.status, "already_redeemed", "second redemption should be refused")
    _assert_eq(again.message, "已兑换过该兑换码", "already redeemed message should come from the facade")
    _assert_eq(host.read(1, RECORD_KEY), "3", "record should not grow on a refused redemption")
  end)

  it("test_record_from_a_previous_session_blocks_redemption", function()
    _install_host({ seed = { ["1|" .. RECORD_KEY] = "2,3" } })

    _assert_eq(redeem.redeem(_state(), 1, "EGG2026").status, "already_redeemed", "archived record should count")
  end)

  it("test_different_players_each_redeem_the_same_code_once", function()
    local host = _install_host()
    local state = _state()

    _assert_eq(redeem.redeem(state, 1, "EGG2026").status, "granted", "player 1 should redeem")
    _assert_eq(redeem.redeem(state, 2, "EGG2026").status, "granted", "player 2 should redeem the same code")
    _assert_eq(redeem.redeem(state, 2, "EGG2026").status, "already_redeemed", "player 2 should be limited to once")
    _assert_eq(host.read(1, RECORD_KEY), "3", "player 1 record")
    _assert_eq(host.read(2, RECORD_KEY), "3", "player 2 record")
    _assert_eq(transaction.owns_product(state, 2, NAILONG), true, "player 2 should own the skin")
  end)

  it("test_multi_skin_code_grants_only_unowned_skins_and_appends_record", function()
    local host = _install_host({ seed = { ["1|" .. CAPYBARA_KEY] = 1, ["1|" .. RECORD_KEY] = "3" } })
    local state = _state()

    local result = redeem.redeem(state, 1, "BUNDLE")

    _assert_eq(result.status, "granted", "partially owned bundle should grant the rest")
    luassert.same({ NAILONG, SPONGEBOB }, result.granted, "only unowned skins should be granted")
    _assert_eq(result.message, "兑换成功，获得：奶龙、海绵宝宝", "message should list granted skins")
    _assert_eq(host.read(1, NAILONG_KEY), 1, "nailong archived")
    _assert_eq(host.read(1, SPONGEBOB_KEY), 1, "spongebob archived")
    _assert_eq(host.read(1, RECORD_KEY), "3,7", "record should append the new code id")
  end)

  it("test_all_rewards_owned_still_records_and_reports_all_owned", function()
    local host = _install_host({ seed = { ["1|" .. NAILONG_KEY] = 1 } })
    local state = _state()

    local result = redeem.redeem(state, 1, "EGG2026")

    _assert_eq(result.status, "all_owned", "fully owned rewards should report all_owned")
    _assert_eq(result.message, "奖励皮肤已全部拥有", "all owned message should come from the facade")
    luassert.same({}, result.granted, "nothing should be granted")
    _assert_eq(host.read(1, RECORD_KEY), "3", "code should still be recorded as redeemed")
    _assert_eq(redeem.redeem(state, 1, "EGG2026").status, "already_redeemed", "and cannot be redeemed again")
  end)

  it("test_archives_unavailable_refuses_without_reading_or_writing", function()
    local host = _install_host({ enabled = false })
    local state = _state()

    local result = redeem.redeem(state, 1, "EGG2026")

    _assert_eq(result.status, "archive_unavailable", "disabled archives should refuse")
    _assert_eq(result.message, "存档未开启，暂时无法兑换", "unavailable message should come from the facade")
    -- lint-allow: call-count 宿主存档读次数是 ADR 0075「存档不可用不读不写」的边界契约
    _assert_eq(host.reads(), 0, "no archive should be read")
    _assert_eq(host.read(1, RECORD_KEY), nil, "no record should be written")
    _assert_eq(transaction.owns_product(state, 1, NAILONG), false, "no skin should be granted this session")
  end)

  it("test_unreadable_record_refuses_as_archive_unavailable", function()
    local host = _install_host({ str_unreadable = true })

    local result
    local warns = _with_warns(function()
      result = redeem.redeem(_state(), 1, "EGG2026")
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
      result = redeem.redeem(state, 1, "EGG2026")
    end)

    _assert_eq(result.status, "write_failed", "unconfirmed record should not count as success")
    _assert_eq(result.message, "兑换失败，请稍后重试", "write failed message should come from the facade")
    luassert.same({ NAILONG }, result.granted, "already granted skin should be reported")
    _assert_eq(host.read(1, NAILONG_KEY), 1, "granted ownership should not be revoked")
    _assert_eq(transaction.owns_product(state, 1, NAILONG), true, "skin stays owned this session")
    local found = false
    for _, line in ipairs(warns) do
      found = found or (line:find("record", 1, true) ~= nil and line:find("code_id=3", 1, true) ~= nil)
    end
    luassert.truthy(found, "record write failure should leave a warn naming the code")

    host.host_opts.str_write_ok = true
    local retry = redeem.redeem(state, 1, "EGG2026")
    _assert_eq(retry.status, "all_owned", "retry should skip the already granted skin")
    _assert_eq(host.read(1, RECORD_KEY), "3", "retry should land the record")
  end)

  it("test_skin_write_failure_leaves_record_unwritten_for_retry", function()
    local host = _install_host({ int_write_ok = false })
    local state = _state()

    local result
    _with_warns(function()
      result = redeem.redeem(state, 1, "EGG2026")
    end)

    _assert_eq(result.status, "write_failed", "unpersisted skin should not count as success")
    _assert_eq(host.read(1, RECORD_KEY), nil, "record should not be written so the player can retry")

    host.host_opts.int_write_ok = true
    local retry = redeem.redeem(state, 1, "EGG2026")
    _assert_eq(retry.status, "granted", "retry should grant the skin into the archive")
    _assert_eq(host.read(1, NAILONG_KEY), 1, "retry should archive ownership")
  end)
end)
