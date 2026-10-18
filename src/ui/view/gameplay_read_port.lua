local number_utils = require("src.foundation.number")

local gameplay_read_port = {}

local function _normalize_level(level)
  local as_int = number_utils.to_integer(level)
  if as_int == nil or as_int < 0 then
    return 0
  end
  return as_int
end

local function _purchase_price(tile)
  if type(tile) ~= "table" then
    return 0
  end
  local price = tile.price
  if not number_utils.is_numeric(price) then
    return 0
  end
  return price
end

-- 与 domain pricing 同语义:升级档位缺失按 0 计。不能用 #costs 封顶——带洞表
-- 的长度是未定义行为({10, nil, 40} 在 Lua 5.4 返回 3、5.5 返回 1),cap 只会让
-- read model 与 domain 在稀疏档位表上偏离(5.5 下 210 vs 250)。
local function _sum_upgrade_costs(costs, max_level)
  local total = 0
  for i = 1, max_level do
    total = total + (costs[i] or 0)
  end
  return total
end

function gameplay_read_port.total_land_invested(tile, level)
  local total = _purchase_price(tile)
  local costs = tile and tile.upgrade_costs or nil
  if type(costs) ~= "table" then
    return total
  end
  return total + _sum_upgrade_costs(costs, _normalize_level(level))
end

return gameplay_read_port

