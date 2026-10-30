-- 表工具:确定性遍历。报告/清单要可复现,就不能靠 pairs 的随机序。
local tables = {}

function tables.count(map)
  local count = 0
  for _ in pairs(map) do
    count = count + 1
  end
  return count
end

function tables.sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

function tables.sorted_pairs(map)
  local keys = tables.sorted_keys(map)
  local index = 0
  return function()
    index = index + 1
    local key = keys[index]
    if key == nil then
      return nil
    end
    return key, map[key]
  end
end

return tables
