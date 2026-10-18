local Class = require("src.foundation.class")

local inventory = Class("Inventory")

function inventory:_notify_change()
  if self._suspend_on_change then
    return
  end
  self._on_change(self)
end

-- 稳定槽位:items 是定长数组(长度恒等于 max_slots),空洞以 false
-- 占位(不用 nil——nil 洞会让 # 与 ipairs 行为不可靠)。一张卡入位后不因其
-- 他卡的进出而移动;消耗/被偷/被弃留洞;新卡填编号最小的洞。
-- 占用槽共用迭代器:跳过空洞(false)与越界空位(nil),判空口径只此一处,
-- count/find_index/nth_occupied_slot 不得各自再写同形循环。
local function _each_occupied(items, max_slots)
  local i = 0
  return function()
    while i < max_slots do
      i = i + 1
      local item = items[i]
      if item then
        return i, item
      end
    end
    return nil
  end
end

function inventory:init(opts)
  opts = opts or {}
  local max_slots = opts.max_slots or (opts.constants and opts.constants.inventory_slots)
  assert(max_slots ~= nil, "Inventory.new(opts) requires opts.max_slots or opts.constants.inventory_slots")

  self.items = {}
  for i = 1, max_slots do
    self.items[i] = false
  end
  self.max_slots = max_slots
  self._on_change = function(_) end
end

function inventory:count()
  local n = 0
  for _ in _each_occupied(self.items, self.max_slots) do
    n = n + 1
  end
  return n
end

function inventory:is_full()
  return self:count() >= self.max_slots
end

function inventory:add(item)
  for i = 1, self.max_slots do
    if not self.items[i] then
      self.items[i] = item
      self:_notify_change()
      return true
    end
  end
  return false
end

-- 空洞(false)与越界(nil)一律返回 nil 且不写表:越界写 false 会撑破
-- #items 恒等于槽位数的红线。
function inventory:remove_by_index(idx)
  local item = self.items[idx]
  if not item then
    return nil
  end
  self.items[idx] = false
  self:_notify_change()
  return item
end

function inventory:find_index(predicate)
  for i, it in _each_occupied(self.items, self.max_slots) do
    if predicate(it) then
      return i
    end
  end
  return nil
end

-- 「第 N 张占用卡 → 槽位号」:随机取卡(偷窃、机会卡弃卡)的落槽映射,
-- 随机数不得直接当槽位号。
function inventory:nth_occupied_slot(n)
  local seen = 0
  for i in _each_occupied(self.items, self.max_slots) do
    seen = seen + 1
    if seen == n then
      return i
    end
  end
  return nil
end

return inventory

