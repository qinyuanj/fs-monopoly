-- #198 / ADR 0075:礼包码码表在加载期校验(User Story 18):id 唯一、code 唯一且
-- 非空、奖励指向存在且配了存档 key 的皮肤。
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

local function _build_error(codes)
  local ok, err = pcall(gift_code_catalog.build, codes, SKINS)
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

  it("test_lookup_ignores_surrounding_spaces_and_letter_case", function()
    local catalog = gift_code_catalog.build({
      { id = 1, code = "Egg2026", rewards = { 5005 } },
    }, SKINS)

    luassert.equal(1, catalog.find("  egg2026 ").id)
    luassert.equal(1, catalog.find("EGG2026").id)
    luassert.is_nil(catalog.find("EGG2027"), "unknown code should not match")
    luassert.is_nil(catalog.find("   "), "blank input should not match")
    luassert.is_nil(catalog.find(nil), "missing input should not match")
  end)

  it("test_rejects_duplicate_id", function()
    local text = _build_error({
      { id = 1, code = "A", rewards = { 5005 } },
      { id = 1, code = "B", rewards = { 5006 } },
    })
    _assert_mentions(text, "duplicate gift code id: 1")
  end)

  it("test_rejects_duplicate_code_after_normalization", function()
    local text = _build_error({
      { id = 1, code = "EGG", rewards = { 5005 } },
      { id = 2, code = " egg ", rewards = { 5006 } },
    })
    _assert_mentions(text, "duplicate gift code: EGG")
  end)

  it("test_rejects_empty_code", function()
    _assert_mentions(_build_error({ { id = 1, code = "  ", rewards = { 5005 } } }), "empty gift code: id=1")
    _assert_mentions(_build_error({ { id = 2, rewards = { 5005 } } }), "empty gift code: id=2")
  end)

  it("test_rejects_reward_pointing_to_missing_skin", function()
    local text = _build_error({ { id = 1, code = "A", rewards = { 9999 } } })
    _assert_mentions(text, "gift code reward is not a skin: id=1 product_id=9999")
  end)

  it("test_rejects_reward_skin_without_archive_key", function()
    local text = _build_error({ { id = 1, code = "A", rewards = { 7001 } } })
    _assert_mentions(text, "gift code reward has no archive_key: id=1 product_id=7001")
  end)

  it("test_rejects_non_positive_integer_id_and_empty_rewards", function()
    _assert_mentions(_build_error({ { id = 0, code = "A", rewards = { 5005 } } }), "invalid gift code id: 0")
    _assert_mentions(_build_error({ { id = 1.5, code = "A", rewards = { 5005 } } }), "invalid gift code id: 1.5")
    _assert_mentions(_build_error({ { id = 1, code = "A", rewards = {} } }), "gift code has no rewards: id=1")
  end)
end)
