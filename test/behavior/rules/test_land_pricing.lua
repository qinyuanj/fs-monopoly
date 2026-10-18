require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
local pricing = require("src.rules.land.pricing")

local function _assert_eq(a, b, msg)
  luassert.truthy(a == b, tostring(msg) .. ": expected " .. tostring(b) .. " got " .. tostring(a))
end

local _config_reset = require("test.support.config_reset")



describe("TestLandPricing", function()
  before_each(function()
    _config_reset.reset_all()
  end)
  it("test_total_invested_returns_purchase_price_for_negative_level", function()
    local tile = {
      price = 400,
      upgrade_costs = { 50, 75, 100 },
    }
    _assert_eq(pricing.total_invested(tile, -3), 400, "negative level should keep purchase price only")
  end)

  it("test_rent_for_level_uses_planning_formula", function()
    local tile = { price = 100, upgrade_costs = { 100, 200, 400 }, rents = { 999, 999, 999, 999 } }
    _assert_eq(pricing.rent_for_level(tile, 0), 50, "level 0 rent should be half base price")
    _assert_eq(pricing.rent_for_level(tile, 1), 100, "level 1 rent should double level 0")
    _assert_eq(pricing.rent_for_level(tile, 2), 200, "level 2 rent should double level 1")
    _assert_eq(pricing.rent_for_level(tile, 3), 400, "level 3 rent should double level 2")
  end)

  it("test_nil_level_falls_back_to_level_zero", function()
    -- #293:rent_for_level/upgrade_cost 的 `level or 0` 默认(0→1 变异)未测。
    local tile = { price = 100, upgrade_costs = { 100, 200, 400 }, rents = { 999, 999, 999, 999 } }
    _assert_eq(pricing.rent_for_level(tile, nil), 50,
      "nil level should behave as level 0")
    _assert_eq(pricing.upgrade_cost(tile, nil), 100,
      "nil level should index the first upgrade cost")
    _assert_eq(pricing.upgrade_cost(tile, 1), 200,
      "level 1 should index the second upgrade cost")
  end)

  it("test_upgrade_cost_without_costs_table_returns_zero", function()
    -- #293:无 upgrade_costs 表的 0 兜底(0→1 变异)未测。
    _assert_eq(pricing.upgrade_cost({ price = 500 }, 2), 0,
      "missing upgrade_costs should yield zero cost")
  end)

  it("test_property_value_total_invested_includes_owner_paid_upgrades", function()
    -- 强征卡支付 = 地价 + owner 已支付的全部升级金币（src/rules/commerce/property_value.lua）
    -- 必须读 tile.upgrade_costs，并与 land/pricing.total_invested 完全一致。
    local property_value = require("src.rules.commerce.property_value")
    local tile = { price = 1000, upgrade_costs = { 1000, 2000, 4000 } }
    _assert_eq(property_value.total_invested(tile, 0), 1000, "level 0 should equal base price")
    _assert_eq(property_value.total_invested(tile, 1), 2000, "level 1 should add first upgrade")
    _assert_eq(property_value.total_invested(tile, 2), 4000, "level 2 should add first two upgrades")
    _assert_eq(property_value.total_invested(tile, 3), 8000, "level 3 should add base + all three upgrades")
    for level = 0, 3 do
      _assert_eq(
        property_value.total_invested(tile, level),
        pricing.total_invested(tile, level),
        "property_value must mirror pricing at level " .. tostring(level)
      )
    end
  end)

-- ===== 迁自 test/property/test_pricing.lua（#190, 测试极简化决策：property 车道退场，性质并入 behavior）=====
end)
local property = require("test.support.property")

-- Generate a land tile with a non-negative purchase price and an upgrade-cost
-- ladder of 0..5 non-negative entries. Non-negative costs/price are what make
-- the monotonicity properties hold; the ladder length (possibly 0) drives the
-- max-level clamp.
local function _gen_tile(rng)
  local ladder = {}
  for _ = 1, rng:int(0, 5) do
    ladder[#ladder + 1] = rng:int(0, 1000)
  end
  return { price = rng:int(0, 5000), upgrade_costs = ladder }
end


describe("TestLandPricingTotalInvestedProperties", function()
  it("test_equals_the_purchase_price_at_level_0_and_at_any_non_positive_level", function()
    property.for_all(_gen_tile, function(tile, rng)
      luassert.truthy(pricing.total_invested(tile, 0) == tile.price, "level 0 invests exactly the purchase price")
      local below = rng:int(-5, 0)
      luassert.truthy(pricing.total_invested(tile, below) == tile.price, "a non-positive level clamps to 0 -> purchase price only")
    end)
  end)

  it("test_is_non_decreasing_as_the_level_rises", function()
    property.for_all(_gen_tile, function(tile)
      local previous = pricing.total_invested(tile, 0)
      for level = 1, #tile.upgrade_costs + 2 do
        local current = pricing.total_invested(tile, level)
        luassert.truthy(current >= previous, "non-negative ladder costs make total_invested non-decreasing in level")
        previous = current
      end
    end)
  end)

  it("test_plateaus_at_and_beyond_the_max_level", function()
    property.for_all(_gen_tile, function(tile, rng)
      local max_level = #tile.upgrade_costs
      local at_max = pricing.total_invested(tile, max_level)
      local beyond = pricing.total_invested(tile, max_level + rng:int(1, 5))
      luassert.truthy(beyond == at_max, "levels past the ladder length clamp to max -> same invested value")
    end)
  end)

  it("test_rises_by_exactly_that_levels_upgrade_cost_on_each_unit_step", function()
    property.for_all(_gen_tile, function(tile)
      -- The k-th step (level k-1 -> k) must add upgrade_costs[k], which is also
      -- what upgrade_cost(tile, k-1) reports: ties the two functions together.
      for k = 1, #tile.upgrade_costs do
        local step = pricing.total_invested(tile, k) - pricing.total_invested(tile, k - 1)
        luassert.truthy(step == pricing.upgrade_cost(tile, k - 1), "step from level k-1 to k must equal upgrade_cost(tile, k-1)")
      end
    end)
  end)

  it("test_stays_at_the_purchase_price_for_any_level_when_there_is_no_upgrade_ladder", function()
    property.for_all(function(rng)
      return { price = rng:int(0, 5000) }
    end, function(tile, rng)
      luassert.truthy(pricing.total_invested(tile, rng:int(-3, 10)) == tile.price, "a tile with no upgrade_costs table never invests beyond its price")
    end)
  end)

end)

describe("TestLandPricingRentForLevelProperties", function()
  it("test_rent_for_level_is_non_decreasing_as_the_level_rises", function()
    property.for_all(_gen_tile, function(tile)
      local previous = pricing.rent_for_level(tile, 0)
      for level = 1, #tile.upgrade_costs + 2 do
        local current = pricing.rent_for_level(tile, level)
        luassert.truthy(current >= previous, "rent must not drop as the level rises")
        previous = current
      end
    end)
  end)

  it("test_doubles_between_consecutive_levels_at_and_above_level_1", function()
    property.for_all(_gen_tile, function(tile)
      -- For 1 <= L <= max_level the priced rent is exactly price * 2^(L-1)
      -- (the * 0.5 cancels a power of two with no fractional remainder), so
      -- each step up doubles the rent.
      local max_level = #tile.upgrade_costs
      for level = 1, max_level - 1 do
        local lower = pricing.rent_for_level(tile, level)
        local higher = pricing.rent_for_level(tile, level + 1)
        luassert.truthy(higher == lower * 2, "rent doubles for each level step at or above level 1")
      end
    end)
  end)

  it("test_rent_for_level_plateaus_at_and_beyond_the_max_level", function()
    property.for_all(_gen_tile, function(tile, rng)
      local max_level = #tile.upgrade_costs
      local at_max = pricing.rent_for_level(tile, max_level)
      local beyond = pricing.rent_for_level(tile, max_level + rng:int(1, 5))
      luassert.truthy(beyond == at_max, "rent clamps to the max-level value beyond the ladder")
    end)
  end)

  it("test_falls_back_to_the_rents_ladder_when_the_tile_has_no_price", function()
    property.for_all(function(rng)
      local rents = {}
      for _ = 1, rng:int(1, 5) do
        rents[#rents + 1] = rng:int(0, 9000)
      end
      return { rents = rents }
    end, function(tile, rng)
      local level = rng:int(0, #tile.rents - 1)
      luassert.truthy(pricing.rent_for_level(tile, level) == tile.rents[level + 1], "an unpriced tile reads the rents ladder directly")
      luassert.truthy(pricing.rent_for_level(tile, #tile.rents + rng:int(1, 3)) == 0, "an out-of-range rents lookup yields 0")
    end)
  end)

end)

describe("TestLandPricingUpgradeCostMaxLevelProperties", function()
  it("test_reports_max_level_as_the_ladder_length", function()
    property.for_all(_gen_tile, function(tile)
      luassert.truthy(pricing.max_level(tile) == #tile.upgrade_costs, "max_level is the number of upgrade-cost entries")
    end)
    property.for_all(function(rng)
      return { price = rng:int(0, 5000) }
    end, function(tile)
      luassert.truthy(pricing.max_level(tile) == 0, "no ladder means max_level 0")
    end)
  end)

  it("test_returns_the_ladder_entry_in_range_and_0_out_of_range", function()
    property.for_all(_gen_tile, function(tile, rng)
      for level = 0, #tile.upgrade_costs - 1 do
        luassert.truthy(pricing.upgrade_cost(tile, level) == tile.upgrade_costs[level + 1], "an in-range level reads its ladder entry")
      end
      luassert.truthy(pricing.upgrade_cost(tile, #tile.upgrade_costs + rng:int(0, 3)) == 0, "a level at or past the ladder length costs 0")
      luassert.truthy(pricing.upgrade_cost(tile, -rng:int(1, 3)) == 0, "a negative level costs 0")
    end)
  end)

end)

describe("TestLandPricingTotalInvestedEdgeCases", function()
  it("test_returns_the_purchase_price_when_upgrade_costs_is_missing", function()
    local tile = { price = 500 }
    luassert.is.same(500, pricing.total_invested(tile, 3))
    luassert.is.same(500, pricing.total_invested(tile, -1))
  end)

  it("test_caps_the_level_by_the_available_ladder_length", function()
    local tile = {
      price = 100,
      upgrade_costs = { 10, 20 },
    }
    luassert.is.same(130, pricing.total_invested(tile, 8))
  end)

-- # 运算在含 nil 洞的 sparse table 上行为未定义；此处用显式 0 表意"零成本项"，
-- 验证 total_invested 不会因中间夹 0 而中断累加。
  it("test_treats_zero_cost_ladder_entries_as_unchanged_non_sparse", function()
    local tile = {
      price = 200,
      upgrade_costs = { 10, 0, 40 },
    }
    luassert.is.same(250, pricing.total_invested(tile, 3))
  end)
end)
