---@generic T
---@class ArrayReadOnly<T>: Array<T>
---@field length integer 数组长度
---@field protected __protected_sequence Array<T> 数组数据
---@field protected __protected_length integer 数组长度
---@field new fun(self: ArrayReadOnly, _array: Array<T>): ArrayReadOnly<T>
local Class = require("src.ui.manager.class")
local Array = require("src.ui.manager.array")
local number_utils = require("src.foundation.number")
local ArrayReadOnly = Class("UIManager.ArrayReadOnly", Array)

-- 只代理元素读（数值下标）；方法名落回类链，不再穿透 backing 实例（#267）：
-- 穿透曾让 ro:append/pop 借到 Array 的实现直接写坏共享 backing(data 与 length 脱节)。
function ArrayReadOnly:__custom_index(key)
    if number_utils.is_numeric(key) then
        return self.__protected_sequence[key]
    end
end

---@param sequence Array<T>
function ArrayReadOnly:init(sequence)
    self.__protected_sequence = sequence
end

-- 方法面由视图类自带(不再从 backing 实例借):只读遍历委托 backing 以自身为 self 执行。
---@param callback fun(e: T)
function ArrayReadOnly:forEach(callback)
    self.__protected_sequence:forEach(callback)
end

-- 只读契约:变更方法 fail-fast 报错(与 Array:__set_length 同款),不做静默 no-op(#267)。
function ArrayReadOnly:append(_value)
    error("ArrayReadOnly is read-only")
end

function ArrayReadOnly:pop()
    error("ArrayReadOnly is read-only")
end

function ArrayReadOnly:__get_length()
    return self.__protected_sequence.__protected_length
end

return ArrayReadOnly

