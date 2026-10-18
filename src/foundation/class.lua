-- foundation.class 最小类系统:Class(name) 造类,:new(...) 造实例并调用 init 构造。
-- 仅支持单一类 + 实例方法;不带多父继承、__get_*/__set_* 魔法、__custom_index、
-- 大写 Init 构造（全仓使用面盘点确认零使用，#48）。

---@class Class
---@field __name string 类名
---@field new fun(self: Class, ...): any 创建类的实例
---@field init fun(self: table, ...) 可选构造函数;:new 调用时若存在则以实例为 self 执行

---@param class_name string 类名(仅作标识,写入实例元表 __name)
---@return Class class_table 类表;在其上定义实例方法,用 class_table:new(...) 造实例
local function Class(class_name)
  local class_table = {
    __name = class_name,
  }
  class_table.__index = class_table

  function class_table:new(...)
    local instance = setmetatable({}, class_table)
    if self.init then
      self.init(instance, ...)
    end
    return instance
  end

  return class_table
end

return Class

