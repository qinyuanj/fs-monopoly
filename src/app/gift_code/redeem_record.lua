-- 兑换记录(#198 / ADR 0075,#195 review 自 redeem 拆出):单个 Str 玩家存档
-- 里逗号分隔的码 id 列表的编解码,是这一存档格式的唯一实现点。
-- 解析跳过非整数片段;追加保留既有文本;空文本即「尚无记录」。
local number_utils = require("src.foundation.number")

local redeem_record = {}

-- 逗号串 → id 数组;非整数片段跳过。
function redeem_record.parse(text)
  local ids = {}
  for token in string.gmatch(text, "[^,]+") do
    local id = number_utils.to_integer(token)
    if id ~= nil then
      ids[#ids + 1] = id
    end
  end
  return ids
end

function redeem_record.contains(ids, id)
  for _, value in ipairs(ids) do
    if value == id then
      return true
    end
  end
  return false
end

function redeem_record.append(record_text, id)
  if record_text == "" then
    return tostring(id)
  end
  return record_text .. "," .. tostring(id)
end

return redeem_record
