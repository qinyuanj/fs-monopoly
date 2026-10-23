-- #198 / #203 / ADR 0075:礼包码码表在加载期校验(User Story 18 / #203 22-24):
-- id 唯一且不撞停用 id、code_hash 为 64 位小写十六进制且唯一、不得出现明文
-- code、奖励指向存在且配了存档 key 的皮肤。查码先规范化输入再按哈希比对。
require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
local gift_code_catalog = require("src.config.content.gift_code_catalog")

local SKINS = {
  { product_id = 5005, name = "奶龙", archive_key = 1054 },
  { product_id = 5006, name = "水豚嘟嘟", archive_key = 1053 },
  { product_id = 7001, name = "无存档皮" },
}

-- 期望哈希由外部 sha256sum 对规范化后的码算出,写死。
local HASH_EGG2026 = "682f05b696b1ca1d9b2818d793b2b352f4128f8ba4fa9db8770cfb279fce1f3f"
local HASH_ABCDEFGHJKMN = "f798776cb4d1e5975b47ed94fcc91314bc8d5c6935ff56b33c03b08c52356818"
local HASH_SUMMER = "20281d1b6cf1a97468ec8153ec64a4f14b0675023b6fc2b32a1e0afcdf689298"

local function _build_error(codes, retired_ids)
  local ok, err = pcall(gift_code_catalog.build, codes, SKINS, retired_ids)
  luassert.is_false(ok, "invalid code table should fail to build")
  local text = tostring(err)
  luassert.is_nil(text:match("^[^\n]-%.lua:%d+: "), "config error should carry no source-position prefix, got: " .. text)
  return text
end

local function _assert_mentions(text, fragment)
  luassert.truthy(text:find(fragment, 1, true) ~= nil, "error should mention " .. fragment .. ", got: " .. text)
end

describe("TestGiftCodes", function()
  it("test_default_code_table_loads_and_registers_redeem_record_key", function()
    package.loaded["src.config.content.gift_codes"] = nil
    package.loaded["src.config.content.gift_code_catalog"] = nil
    local gift_codes = require("src.config.content.gift_codes")
    local catalog = require("src.config.content.gift_code_catalog")

    luassert.is_number(gift_codes.redeem_record_archive_key, "redeem record Str key should be registered")
    luassert.is_table(catalog.default(), "default code table should build at load time")
  end)

  -- #203:测试码 TEST2026(id 1)已停用,码表里只剩哈希,明文不再命中。
  it("test_default_code_table_retires_id_1_and_no_longer_accepts_test2026", function()
    local gift_codes = require("src.config.content.gift_codes")

    luassert.same({ 1 }, gift_codes.retired_ids, "id 1 should be registered as retired")
    luassert.is_nil(gift_code_catalog.default().find("TEST2026"), "the retired plaintext test code should not match")
  end)

  it("test_lookup_ignores_case_hyphens_and_any_whitespace", function()
    local catalog = gift_code_catalog.build({
      { id = 1, code_hash = HASH_ABCDEFGHJKMN, rewards = { 5005 }, note = "#203" },
    }, SKINS)

    for _, input in ipairs({ "ABCDEFGHJKMN", "ABCD-EFGH-JKMN", "abcd-efgh-jkmn", "  AbCd EFGH\t-jkmn \n" }) do
      local entry = catalog.find(input)
      luassert.is_not_nil(entry, "input should match: [" .. input .. "]")
      luassert.equal(1, entry.id)
    end
    luassert.is_nil(catalog.find("ABCD-EFGH-JKMP"), "unknown code should not match")
    luassert.is_nil(catalog.find(HASH_ABCDEFGHJKMN), "the stored hash itself should not match")
    luassert.is_nil(catalog.find("  - "), "blank input should not match")
    luassert.is_nil(catalog.find(nil), "missing input should not match")
  end)

  it("test_rejects_plaintext_code_field", function()
    local text = _build_error({ { id = 1, code = "EGG2026", code_hash = HASH_EGG2026, rewards = { 5005 } } })
    _assert_mentions(text, "gift code must not carry plaintext code: id=1")
  end)

  it("test_rejects_missing_or_malformed_code_hash", function()
    _assert_mentions(_build_error({ { id = 1, rewards = { 5005 } } }), "invalid gift code_hash: id=1")
    _assert_mentions(_build_error({ { id = 2, code_hash = string.upper(HASH_EGG2026), rewards = { 5005 } } }),
      "invalid gift code_hash: id=2")
    _assert_mentions(_build_error({ { id = 3, code_hash = HASH_EGG2026:sub(2), rewards = { 5005 } } }),
      "invalid gift code_hash: id=3")
    _assert_mentions(_build_error({ { id = 4, code_hash = HASH_EGG2026 .. "0", rewards = { 5005 } } }),
      "invalid gift code_hash: id=4")
    _assert_mentions(_build_error({ { id = 5, code_hash = ("g"):rep(64), rewards = { 5005 } } }),
      "invalid gift code_hash: id=5")
  end)

  it("test_rejects_duplicate_code_hash", function()
    local text = _build_error({
      { id = 1, code_hash = HASH_EGG2026, rewards = { 5005 } },
      { id = 2, code_hash = HASH_EGG2026, rewards = { 5006 } },
    })
    _assert_mentions(text, "duplicate gift code_hash: id=2")
  end)

  it("test_rejects_id_that_collides_with_a_retired_id", function()
    local text = _build_error({ { id = 1, code_hash = HASH_EGG2026, rewards = { 5005 } } }, { 1 })
    _assert_mentions(text, "gift code id is retired: 1")
  end)

  it("test_rejects_non_positive_integer_retired_id", function()
    _assert_mentions(_build_error({}, { 0 }), "invalid retired gift code id: 0")
  end)

  it("test_rejects_duplicate_id", function()
    local text = _build_error({
      { id = 1, code_hash = HASH_EGG2026, rewards = { 5005 } },
      { id = 1, code_hash = HASH_SUMMER, rewards = { 5006 } },
    })
    _assert_mentions(text, "duplicate gift code id: 1")
  end)

  it("test_rejects_reward_pointing_to_missing_skin", function()
    local text = _build_error({ { id = 1, code_hash = HASH_EGG2026, rewards = { 9999 } } })
    _assert_mentions(text, "gift code reward is not a skin: id=1 product_id=9999")
  end)

  it("test_rejects_reward_skin_without_archive_key", function()
    local text = _build_error({ { id = 1, code_hash = HASH_EGG2026, rewards = { 7001 } } })
    _assert_mentions(text, "gift code reward has no archive_key: id=1 product_id=7001")
  end)

  it("test_rejects_non_positive_integer_id_and_empty_rewards", function()
    _assert_mentions(_build_error({ { id = 0, code_hash = HASH_EGG2026, rewards = { 5005 } } }), "invalid gift code id: 0")
    _assert_mentions(_build_error({ { id = 1.5, code_hash = HASH_EGG2026, rewards = { 5005 } } }),
      "invalid gift code id: 1.5")
    _assert_mentions(_build_error({ { id = 1, code_hash = HASH_EGG2026, rewards = {} } }), "gift code has no rewards: id=1")
  end)

  -- expires_at 可选,配了就必须是数值(墙钟秒);配错类型在加载期暴露,
  -- 不留给兑换时静默不判过期(#195 review)。
  it("test_rejects_non_numeric_expires_at", function()
    _assert_mentions(_build_error({ { id = 1, code_hash = HASH_EGG2026, rewards = { 5005 }, expires_at = "2026-12-31" } }),
      "invalid gift code expires_at: id=1")
    _assert_mentions(_build_error({ { id = 2, code_hash = HASH_SUMMER, rewards = { 5005 }, expires_at = true } }),
      "invalid gift code expires_at: id=2")
  end)

  it("test_accepts_absent_and_numeric_expires_at", function()
    local catalog = gift_code_catalog.build({
      { id = 1, code_hash = HASH_EGG2026, rewards = { 5005 } },
      { id = 2, code_hash = HASH_SUMMER, rewards = { 5006 }, expires_at = 1893456000 },
    }, SKINS)

    luassert.equal(1, catalog.find("egg2026").id, "a code without expires_at should build")
    luassert.equal(2, catalog.find("summer").id, "a numeric expires_at should build")
  end)
end)
