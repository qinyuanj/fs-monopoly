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

