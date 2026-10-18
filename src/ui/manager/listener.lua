---@class UIManager.Listener : Class
---@field _event string 事件名称
---@field _callback function 回调函数
---@field _node_id ENode 节点ID
---@field _trigger integer 触发器
local Class = require("src.ui.manager.class")
local context = require("src.ui.manager.context")
local host_events = require("src.ui.seams.host_events")
local Listener = Class("UIManager.Listener")
local event_handlers = context.event_handlers

function Listener:init() end

---@param callbacks function[]
---@param target function
local function _remove_callback(callbacks, target)
    for i, callback in ipairs(callbacks) do
        if callback == target then
            table.remove(callbacks, i)
            break
        end
    end
end

-- 事件处理器上是否还挂着节点处理器（trigger 是元数据，不算节点）
---@param handler table
---@return boolean
local function _has_node_handlers(handler)
    for key in pairs(handler) do
        if key ~= "trigger" then
            return true
        end
    end
    return false
end

-- 没有节点处理器时注销宿主自定义事件并丢弃整个处理器
---@param handler table
---@param event string
local function _prune_event(handler, event)
    if _has_node_handlers(handler) then
        return
    end
    host_events.unregister_custom_event(handler.trigger)
    event_handlers[event] = nil
end

---@param handler table
---@param listener UIManager.Listener
local function _detach(handler, listener)
    local handler_data = handler[listener._node_id]
    if not handler_data or not handler_data.callbacks then
        return
    end

    _remove_callback(handler_data.callbacks, listener._callback)

    if #handler_data.callbacks == 0 then
        handler[listener._node_id] = nil
    end

    _prune_event(handler, listener._event)
end

function Listener:destroy()
    local handler = event_handlers[self._event]
    if handler then
        _detach(handler, self)
    end
end

return Listener

