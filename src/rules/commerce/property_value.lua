-- 地块总投入:规则层唯一实现(#212 / #206 D),供资产统计、落地规则、效果支付、
-- 拆除选择与道具可用性统一调用。放在 commerce 而非 land:items 与 land 都向它依赖,
-- 放进 land 会构成 rules.items <-> rules.land 投影环。
-- ui 只读副本见 src/ui/view/gameplay_read_port.lua,由契约测试钉住同语义。
local number_utils = require("src.foundation.number")

local property_value = {}

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

-- 地价 + 1..档位逐级升级费。缺失档位按 0 计,不用 #costs 封顶:
-- 带洞表的长度在 Lua 5.4/5.5 上不一致({10, nil, 40} 分别为 3 与 1)。
function property_value.total_invested(tile, level)
  assert(tile ~= nil, "missing tile")
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

return property_value
