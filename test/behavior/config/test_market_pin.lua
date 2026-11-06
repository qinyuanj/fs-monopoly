require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
-- market.lua 数据契约 pin:整表逐条深等(#293 变异清扫)。
-- 商品目录(档位/价格/货币)被商店流程消费,改表必须改契约。
local market = require("src.config.content.market")

local expected = {
  { order = 1,  product_id = 2003, name = "骰子加倍卡", page = "道具商店", kind = "item", currency = "金币",  price = 5000 },
  { order = 2,  product_id = 2002, name = "遥控骰子卡", page = "道具商店", kind = "item", currency = "乐园币", price = 100 },
  { order = 3,  product_id = 2005, name = "地雷卡",    page = "道具商店", kind = "item", currency = "乐园币", price = 200 },
  { order = 4,  product_id = 2012, name = "流放卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 5 },
  { order = 5,  product_id = 2004, name = "路障卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 5 },
  { order = 6,  product_id = 2006, name = "清障卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 5 },
  { order = 7,  product_id = 2001, name = "免费卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 5 },
  { order = 8,  product_id = 2007, name = "偷窃卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 10 },
  { order = 9,  product_id = 2008, name = "怪兽卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 10 },
  { order = 10, product_id = 2009, name = "强征卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 10 },
  { order = 11, product_id = 2013, name = "导弹卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 10 },
  { order = 12, product_id = 2017, name = "财神卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 15 },
  { order = 13, product_id = 2018, name = "穷神卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 15 },
  { order = 14, product_id = 2019, name = "天使卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 15 },
  { order = 15, product_id = 2010, name = "免税卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 28 },
  { order = 16, product_id = 2015, name = "请神卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 28 },
  { order = 17, product_id = 2016, name = "送神卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 28 },
  { order = 18, product_id = 2011, name = "均富卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 58 },
  { order = 19, product_id = 2014, name = "查税卡",    page = "道具商店", kind = "item", currency = "金豆",  price = 58 },
}

describe("TestMarketPin", function()

  it("test_market_catalog_matches_the_pinned_contract", function()
    luassert.truthy(#market == #expected, "market row count must match")
    for i, want in ipairs(expected) do
      luassert.truthy(market[i] ~= nil, "row " .. i .. " must exist")
      luassert.truthy(market[i].order == want.order, "row " .. i .. " order")
      luassert.truthy(market[i].product_id == want.product_id, "row " .. i .. " product_id")
      luassert.truthy(market[i].name == want.name, "row " .. i .. " name")
      luassert.truthy(market[i].page == want.page, "row " .. i .. " page")
      luassert.truthy(market[i].kind == want.kind, "row " .. i .. " kind")
      luassert.truthy(market[i].currency == want.currency, "row " .. i .. " currency")
      luassert.truthy(market[i].price == want.price, "row " .. i .. " price")
    end
  end)

  -- 付费商品的值是编辑器地图商城限购数量的镜像,改编辑器必须同步这里(ADR 0080);
  -- 金币商品的值只在这里维护(ADR 0081)。
  it("test_every_item_has_a_purchase_limit_of_ten", function()
    local item_count = 0
    for _, row in ipairs(market) do
      item_count = item_count + 1
      luassert.is.equal(10, row.purchase_limit, row.name .. " purchase_limit")
    end
    luassert.is.equal(19, item_count, "item count")
  end)

end)
