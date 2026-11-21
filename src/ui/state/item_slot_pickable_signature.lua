-- 可选槽位集合的规范签名(#594)。纯派生,无宿主副作用:两侧「集合是否变了」
-- 的判定必须字面同口径,所以这个派生只有这一处实现。
--
-- 住在 ui.state 而非 ui.coord:ui.coord 可以依赖 ui.state,反向禁止
-- (docs/architecture.md),而重放记忆(ui.state)也要用它。
local M = {}

local _parts = {}

-- 可选槽位编号升序拼成签名。空集合是 "" —— 与「无记忆」(nil)是不同状态,
-- 调用方不得把两者混为一谈。
function M.of(slot_pickable)
  local count = 0
  for index, can_pick in ipairs(slot_pickable) do
    if can_pick then
      count = count + 1
      _parts[count] = tostring(index)
    end
  end
  for i = count + 1, #_parts do
    _parts[i] = nil
  end
  return table.concat(_parts, ",")
end

return M

