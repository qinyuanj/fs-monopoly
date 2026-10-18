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

--[[ mutate4lua-manifest
version=4
projectHash=87e6c827c7ff3458
scope.0.id=chunk:src/player/actions/inventory.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=102
scope.0.semanticHash=ed1e4be6092ce1f5
scope.1.id=function:inventory:_notify_change
scope.1.kind=function
scope.1.startLine=5
scope.1.endLine=10
scope.1.semanticHash=89c53bdf3a8fc65a
scope.2.id=function:_each_occupied
scope.2.kind=function
scope.2.startLine=17
scope.2.endLine=29
scope.2.semanticHash=c6a79e74aa421ff6
scope.3.id=function:<anonymous>
scope.3.kind=function
scope.3.startLine=19
scope.3.endLine=28
scope.3.semanticHash=b46a5e9f2b1bde8d
scope.4.id=function:inventory:init
scope.4.kind=function
scope.4.startLine=31
scope.4.endLine=42
scope.4.semanticHash=162918c406c75794
scope.5.id=function:self._on_change
scope.5.kind=function
scope.5.startLine=41
scope.5.endLine=41
scope.5.semanticHash=e632431f3ceaa0c1
scope.6.id=function:inventory:count
scope.6.kind=function
scope.6.startLine=44
scope.6.endLine=50
scope.6.semanticHash=c2a006e486022d1e
scope.7.id=function:inventory:is_full
scope.7.kind=function
scope.7.startLine=52
scope.7.endLine=54
scope.7.semanticHash=8ededd5958b5da67
scope.8.id=function:inventory:add
scope.8.kind=function
scope.8.startLine=56
scope.8.endLine=65
scope.8.semanticHash=460e08eaca9ef079
scope.9.id=function:inventory:remove_by_index
scope.9.kind=function
scope.9.startLine=69
scope.9.endLine=77
scope.9.semanticHash=3c3124a5327cceaa
scope.10.id=function:inventory:find_index
scope.10.kind=function
scope.10.startLine=79
scope.10.endLine=86
scope.10.semanticHash=58bb1b24fee5e67b
scope.11.id=function:inventory:nth_occupied_slot
scope.11.kind=function
scope.11.startLine=90
scope.11.endLine=99
scope.11.semanticHash=d05d7fdc32541ac4
]]
