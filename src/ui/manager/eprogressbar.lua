---@class UIManager.EProgressbar : UIManager.ENode
---@field __name "UIManager.EProgressbar"
---@field value integer 进度值
---@field max_value integer 最大进度值
---@field min_value integer 最小进度值
---@field transition_time Fixed 样式变化时间
---@field protected __protected_value integer 进度值
---@field protected __protected_max_value integer 最大进度值
---@field protected __protected_min_value integer 最小进度值
---@field protected __protected_transition_time Fixed 受保护的样式变化时间
local Class = require("src.ui.manager.class")
local ENode = require("src.ui.manager.enode")
local push = require("src.ui.manager.host_push").push
local EProgressbar = Class("UIManager.EProgressbar", ENode)

---@param node ENode
---@param name string
function EProgressbar:init(node, name)
    ENode.init(self, node, name)
    self.__protected_transition_time = 0.0
end

function EProgressbar:__get_value()
    return self.__protected_value
end

function EProgressbar:__set_value(value)
    self.__protected_value = value
    self:__update_value()
end

function EProgressbar:__update_value()
    push(function(role)
        role.set_progressbar_transition(self.__protected_id, self.__protected_value, self.__protected_transition_time)
    end)
end

function EProgressbar:__get_max_value()
    return self.__protected_max_value
end

function EProgressbar:__set_max_value(value)
    self.__protected_max_value = value
    self:__update_max_value()
end

function EProgressbar:__update_max_value()
    push(function(role)
        role.set_progressbar_max(self.__protected_id, self.__protected_max_value)
    end)
end

function EProgressbar:__get_min_value()
    return self.__protected_min_value
end

function EProgressbar:__set_min_value(value)
    self.__protected_min_value = value
    self:__update_min_value()
end

function EProgressbar:__update_min_value()
    push(function(role)
        role.set_progressbar_min(self.__protected_id, self.__protected_min_value)
    end)
end

function EProgressbar:__get_transition_time()
    return self.__protected_transition_time
end

function EProgressbar:__set_transition_time(value)
    self.__protected_transition_time = value
end

return EProgressbar

