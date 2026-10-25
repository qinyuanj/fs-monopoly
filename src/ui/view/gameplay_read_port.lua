local number_utils = require("src.foundation.number")

local gameplay_read_port = {}

-- 地块总投入的 ui 只读副本(#212 / #206 D)。ui_no_rules 不允许引规则层,
-- 故与 src/rules/commerce/property_value.lua 的 total_invested 各写一份,由
-- test/contract/ui/test_read_model.lua 钉住同语义;唯一差别是 nil 地块返回 0
-- (展示侧容错),规则层断言失败。

-- 档位 nil、负数、非整数(含字符串)一律按 0 计。
local function _invested_level(level)
  if not number_utils.is_numeric(level) then
    return 0
  end
  local as_int = number_utils.to_integer(level)
  if as_int == nil or as_int ~= level or as_int < 0 then
    return 0
  end
  return as_int
end

local function _invested_price(tile)
  local price = tile.price
  if number_utils.is_numeric(price) then
    return price
  end
  return 0
end

-- 缺失档位按 0 计。不能用 #costs 封顶——带洞表的长度是未定义行为
-- ({10, nil, 40} 在 Lua 5.4 返回 3、5.5 返回 1)。
function gameplay_read_port.total_land_invested(tile, level)
  if tile == nil then
    return 0
  end
  local total = _invested_price(tile)
  local costs = tile.upgrade_costs
  if type(costs) ~= "table" then
    return total
  end
  for i = 1, _invested_level(level) do
    total = total + (costs[i] or 0)
  end
  return total
end

return gameplay_read_port
