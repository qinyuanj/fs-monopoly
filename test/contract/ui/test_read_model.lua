local luassert = assert
local gameplay_read_port = require("src.ui.view.gameplay_read_port")
local property_value = require("src.rules.commerce.property_value")

-- #212(#206 D):ui 只读副本(ui_no_rules 不允许 ui 引规则层)与规则层唯一的地块总投入
-- 函数同语义。同一组样例同时喂给两边,断言逐条相等;唯一差别 nil 地块单独钉。
local _ladder = { 100, 150, 220 }
local _samples = {
  { name = "typical level 0", tile = { price = 300, upgrade_costs = _ladder }, level = 0 },
  { name = "typical level 2", tile = { price = 300, upgrade_costs = _ladder }, level = 2 },
  { name = "typical max level", tile = { price = 300, upgrade_costs = _ladder }, level = 3 },
  { name = "level beyond ladder", tile = { price = 300, upgrade_costs = _ladder }, level = 7 },
  { name = "nil level", tile = { price = 300, upgrade_costs = _ladder }, level = nil },
  { name = "negative level", tile = { price = 300, upgrade_costs = _ladder }, level = -1 },
  { name = "non-integer level", tile = { price = 300, upgrade_costs = _ladder }, level = 1.5 },
  { name = "numeric string level", tile = { price = 300, upgrade_costs = _ladder }, level = "2" },
  { name = "integral float level", tile = { price = 300, upgrade_costs = _ladder }, level = 2.0 },
  { name = "non-numeric price", tile = { price = "abc", upgrade_costs = _ladder }, level = 1 },
  { name = "numeric string price", tile = { price = "300", upgrade_costs = _ladder }, level = 1 },
  { name = "missing price", tile = { upgrade_costs = _ladder }, level = 1 },
  { name = "missing ladder", tile = { price = 500 }, level = 3 },
  { name = "non-table ladder", tile = { price = 500, upgrade_costs = 10 }, level = 3 },
  { name = "sparse ladder", tile = { price = 200, upgrade_costs = { 10, nil, 40 } }, level = 3 },
  { name = "zero entry ladder", tile = { price = 200, upgrade_costs = { 10, 0, 40 } }, level = 3 },
  { name = "empty tile", tile = {}, level = 0 },
}

describe("TestReadModel", function()

it("test_total_land_invested_matches_rules_total_invested_on_shared_samples", function()
  for _, sample in ipairs(_samples) do
    luassert.is.equal(
      property_value.total_invested(sample.tile, sample.level),
      gameplay_read_port.total_land_invested(sample.tile, sample.level),
      "ui read model must match rules total_invested: " .. sample.name
    )
  end
end)

it("test_total_land_invested_tolerates_a_nil_tile_where_rules_assert", function()
  luassert.is.equal(0, gameplay_read_port.total_land_invested(nil, 2))
  luassert.has_error(function()
    property_value.total_invested(nil, 2)
  end, "missing tile")
end)

end)
