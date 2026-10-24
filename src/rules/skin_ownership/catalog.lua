-- 皮肤目录(#204 皮肤归属内部):静态皮肤配置的查询与排序视图。每次调用都读当前
-- 配置,不缓存快照。
local skins = require("src.config.content.skins")

local catalog = {}

local function _price_before(price_a, price_b)
  if price_a == nil then
    return false
  end
  if price_b == nil then
    return true
  end
  return price_a < price_b
end

-- 目录排序真源（#495 裁定）：price 递增为主键（最便宜的皮肤在槽位1），order
-- 字段为同价 tie-break，源下标兜底保证全等键稳定；price 缺失的皮肤排最后。
function catalog.sorted()
  local decorated = {}
  for index, skin in ipairs(skins) do
    decorated[#decorated + 1] = { skin = skin, source_index = index }
  end
  table.sort(decorated, function(a, b)
    local price_a = a.skin.price
    local price_b = b.skin.price
    if price_a ~= price_b then
      return _price_before(price_a, price_b)
    end
    local order_a, order_b = a.skin.order or 0, b.skin.order or 0
    if order_a ~= order_b then
      return order_a < order_b
    end
    return a.source_index < b.source_index
  end)
  local sorted = {}
  for index, entry in ipairs(decorated) do
    sorted[index] = entry.skin
  end
  return sorted
end

function catalog.skin_by_product(product_id)
  if product_id == nil then
    return nil
  end
  for _, skin in ipairs(skins) do
    if skin.product_id == product_id then
      return skin
    end
  end
  return nil
end

return catalog
