---@generic T
---@class Array<T>: Class
---@field [integer] T 数组元素
---@field length integer 数组长度
---@field protected __protected_data T[] 数组数据
---@field protected __protected_length integer 数组长度
---@field new fun(self: Array): Array<T>
local Class = require("src.ui.manager.class")
local Array = Class("Array")

function Array:__custom_index(key)
    return self.__protected_data[key]
end

function Array:init()
    self.__protected_data = {}
    self.__protected_length = 0
end

---@param callback fun(e: T)
function Array:forEach(callback)
    for i = 1, self.__protected_length do
        callback(self.__protected_data[i])
    end
end

function Array:append(value)
    self.__protected_length = self.__protected_length + 1
    self.__protected_data[self.__protected_length] = value
end

function Array:pop()
    local value = self.__protected_data[self.__protected_length]
    self.__protected_data[self.__protected_length] = nil
    self.__protected_length = self.__protected_length - 1
    return value
end

function Array:__get_length()
    return self.__protected_length
end

function Array:__set_length(value)
    error("Array length is read-only")
end

return Array

