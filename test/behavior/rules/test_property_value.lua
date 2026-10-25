require("test.bootstrap").install_package_paths()
local luassert = require("luassert")
-- property_value.lua 直测:规则层唯一的地块总投入函数(#212 / #206 D)。
-- 数值缺省(0→1 变异)被资产统计、强征判定与拆除估值直接消费,必须钉住。

local property_value = require("src.rules.commerce.property_value")
local pricing = require("src.rules.land.pricing")
local property = require("test.support.property")

describe("TestPropertyValueTotalInvestedBoundaries", function()
  it("test_rejects_a_nil_tile_as_caller_error", function()
    luassert.has_error(function()
      property_value.total_invested(nil, 1)
    end, "missing tile")
  end)

  it("test_counts_a_nil_level_as_level_zero", function()
    luassert.is.same(100, property_value.total_invested({ price = 100 }, nil))
    luassert.is.same(100, property_value.total_invested({ price = 100, upgrade_costs = { 50 } }, nil))
  end)

  it("test_counts_a_negative_level_as_level_zero", function()
    luassert.is.same(100, property_value.total_invested({ price = 100, upgrade_costs = { 50 } }, -2))
    luassert.is.same(400, property_value.total_invested({ price = 400, upgrade_costs = { 50, 75, 100 } }, -3))
  end)

  it("test_counts_a_non_integer_level_as_level_zero", function()
    luassert.is.same(100, property_value.total_invested({ price = 100, upgrade_costs = { 50, 70 } }, 1.5))
    luassert.is.same(100, property_value.total_invested({ price = 100, upgrade_costs = { 50, 70 } }, "2"))
  end)

  it("test_accepts_an_integral_float_level", function()
    luassert.is.same(220, property_value.total_invested({ price = 100, upgrade_costs = { 50, 70 } }, 2.0))
  end)

  it("test_counts_a_non_numeric_or_missing_price_as_zero", function()
    luassert.is.same(50, property_value.total_invested({ price = "abc", upgrade_costs = { 50 } }, 1))
    luassert.is.same(50, property_value.total_invested({ price = "100", upgrade_costs = { 50 } }, 1))
    luassert.is.same(0, property_value.total_invested({}, 0))
  end)

  it("test_returns_the_price_when_upgrade_costs_is_missing", function()
    luassert.is.same(500, property_value.total_invested({ price = 500 }, 3))
    luassert.is.same(500, property_value.total_invested({ price = 500, upgrade_costs = 10 }, 3))
  end)

  it("test_counts_holes_in_a_sparse_ladder_as_zero_without_length_cap", function()
    -- {10, nil, 40} 的 # 在 5.4 是 3、5.5 是 1;逐级累加不得受表长度影响。
    luassert.is.same(250, property_value.total_invested({ price = 200, upgrade_costs = { 10, nil, 40 } }, 3))
    luassert.is.same(250, property_value.total_invested({ price = 200, upgrade_costs = { 10, 0, 40 } }, 3))
  end)

  it("test_counts_levels_beyond_the_ladder_as_zero", function()
    luassert.is.same(150, property_value.total_invested({ price = 100, upgrade_costs = { 50 } }, 4))
    luassert.is.same(130, property_value.total_invested({ price = 100, upgrade_costs = { 10, 20 } }, 8))
    luassert.is.same(100, property_value.total_invested({ price = 100, upgrade_costs = {} }, 2))
  end)

  it("test_sums_price_plus_each_paid_upgrade", function()
    -- 强征卡支付 = 地价 + owner 已支付的全部升级金币。
    local tile = { price = 1000, upgrade_costs = { 1000, 2000, 4000 } }
    luassert.is.same(1000, property_value.total_invested(tile, 0))
    luassert.is.same(2000, property_value.total_invested(tile, 1))
    luassert.is.same(4000, property_value.total_invested(tile, 2))
    luassert.is.same(8000, property_value.total_invested(tile, 3))
  end)
end)

-- ===== 迁自 test_land_pricing.lua(原 test/property/test_pricing.lua,#190)=====
-- Generate a land tile with a non-negative purchase price and an upgrade-cost
-- ladder of 0..5 non-negative entries. Non-negative costs/price are what make
-- the monotonicity properties hold.
local function _gen_tile(rng)
  local ladder = {}
  for _ = 1, rng:int(0, 5) do
    ladder[#ladder + 1] = rng:int(0, 1000)
  end
  return { price = rng:int(0, 5000), upgrade_costs = ladder }
end

describe("TestPropertyValueTotalInvestedProperties", function()
  it("test_equals_the_purchase_price_at_level_0_and_at_any_non_positive_level", function()
    property.for_all(_gen_tile, function(tile, rng)
      luassert.truthy(property_value.total_invested(tile, 0) == tile.price, "level 0 invests exactly the purchase price")
      local below = rng:int(-5, 0)
      luassert.truthy(property_value.total_invested(tile, below) == tile.price, "a non-positive level counts as 0 -> purchase price only")
    end)
  end)

  it("test_is_non_decreasing_as_the_level_rises", function()
    property.for_all(_gen_tile, function(tile)
      local previous = property_value.total_invested(tile, 0)
      for level = 1, #tile.upgrade_costs + 2 do
        local current = property_value.total_invested(tile, level)
        luassert.truthy(current >= previous, "non-negative ladder costs make total_invested non-decreasing in level")
        previous = current
      end
    end)
  end)

  it("test_plateaus_at_and_beyond_the_max_level", function()
    property.for_all(_gen_tile, function(tile, rng)
      local max_level = #tile.upgrade_costs
      local at_max = property_value.total_invested(tile, max_level)
      local beyond = property_value.total_invested(tile, max_level + rng:int(1, 5))
      luassert.truthy(beyond == at_max, "levels past the ladder add zero -> same invested value")
    end)
  end)

  it("test_rises_by_exactly_that_levels_upgrade_cost_on_each_unit_step", function()
    property.for_all(_gen_tile, function(tile)
      -- The k-th step (level k-1 -> k) must add upgrade_costs[k], which is also
      -- what pricing.upgrade_cost(tile, k-1) reports: ties the two functions together.
      for k = 1, #tile.upgrade_costs do
        local step = property_value.total_invested(tile, k) - property_value.total_invested(tile, k - 1)
        luassert.truthy(step == pricing.upgrade_cost(tile, k - 1), "step from level k-1 to k must equal upgrade_cost(tile, k-1)")
      end
    end)
  end)

  it("test_stays_at_the_purchase_price_for_any_level_when_there_is_no_upgrade_ladder", function()
    property.for_all(function(rng)
      return { price = rng:int(0, 5000) }
    end, function(tile, rng)
      luassert.truthy(property_value.total_invested(tile, rng:int(-3, 10)) == tile.price, "a tile with no upgrade_costs table never invests beyond its price")
    end)
  end)
end)
