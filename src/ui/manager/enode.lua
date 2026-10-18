---@class UIManager.ENode : Class
---@field __name "UIManager.ENode"
---@field id ENode ID值 - 只读
---@field name string UI名称 - 只读
---@field parent UIManager.ENode? 父亲节点 - 只读
---@field children ArrayReadOnly<UIManager.ENode> 子节点列表 - 只读
---@field visible boolean 是否可见
---@field disabled boolean 是否禁用
---@field custom_data table 自定义数据
---@field client_data table<RoleID, table> 客户端数据
---@field protected __protected_id ENode 受保护的id值
---@field protected __protected_name string 受保护的UI名称
---@field protected __protected_parent UIManager.ENode 受保护的父亲节点
---@field protected __protected_children Array<UIManager.ENode> 受保护的子节点列表
---@field protected __protected_visible boolean 受保护的是否可见
---@field protected __protected_disabled boolean 受保护的是否禁用
---@field protected __protected_custom_data table<RoleID, table> 受保护的自定义数据
---@field new fun(self: UIManager.ENode, node: ENode, name: string)
local Class = require("src.ui.manager.class")
local context = require("src.ui.manager.context")
local Array = require("src.ui.manager.array")
local ArrayReadOnly = require("src.ui.manager.array_read_only")
local Listener = require("src.ui.manager.listener")
local host_events = require("src.ui.seams.host_events")
local push = require("src.ui.manager.host_push").push
local ENode = Class("UIManager.ENode")
local nodes_list = context.nodes_list

local event_handlers = context.event_handlers

function ENode.__custom_index(tbl, key)
    if string.sub(key, 1, 12) == "__protected_" then
        local role = context.client_role
        if role then
            local client_data = tbl.client_data
            local data = client_data[role.get_roleid()]
            if not data then
                return client_data[-1][key]
            end
            if not data[key] then
                return client_data[-1][key]
            end
            return data[key]
        else
            return tbl.client_data[-1][key]
        end
    end
end

function ENode.__new_custom_index(tbl, key, value)
    if string.sub(key, 1, 12) == "__protected_" then
        local role = context.client_role
        if role then
            local client_data = tbl.client_data
            if not client_data[role.get_roleid()] then
                client_data[role.get_roleid()] = {}
            end
            local data = client_data[role.get_roleid()]
            data[key] = value
        else
            local client_data = tbl.client_data
            client_data[-1][key] = value
        end
        return
    end
    rawset(tbl, key, value)
end

---@param node ENode
---@param name string
function ENode:init(node, name)
    if nodes_list[node] then
        nodes_list[node] = nil
    end
    nodes_list[node] = self
    self.client_data = { [-1] = {} }
    self.__protected_custom_data = {}
    self.__protected_name = name
    self.__protected_parent = nil
    self.__protected_id = node

    local array = Array:new() --[[@as Array<UIManager.ENode>]]
    self.__protected_children = array
    self.__protected_read_only_children = ArrayReadOnly:new(array)
end

function ENode:__init_children()
    for idx, node in ipairs(GameAPI.get_eui_children(self.id)) do
        local uinode = nodes_list[node] --[[@as UIManager.ENode]]
        uinode.__protected_parent = self
        self.__protected_children:append(uinode)
    end
end

function ENode:__get_children()
    return self.__protected_read_only_children
end

function ENode:__set_children(value)
    warn(("attempt to set a read-only value field 'children' of '%s'"):format(self.__protected_name))
end

function ENode:__get_custom_data()
    return self.__protected_custom_data
end

function ENode:__set_custom_data(value)
    self.__protected_custom_data = value
end

function ENode:__get_parent()
    return self.__protected_parent
end

function ENode:__set_parent(value)
    warn(("attempt to set a read-only value field 'parent' of '%s'"):format(self.__name))
end

function ENode:__get_name()
    return self.__protected_name
end

function ENode:__set_name(value)
    warn(("attempt to set a read-only value field 'name' of '%s'"):format(self.__name))
end

function ENode:__get_id()
    return self.__protected_id
end

function ENode:__set_id(value)
    warn(("attempt to set a read-only value field 'id' of '%s'"):format(self.__name))
end

function ENode:__get_visible()
    return self.__protected_visible
end

function ENode:__set_visible(value)
    self.__protected_visible = value
    self:__update_visible()
end

function ENode:__update_visible()
    push(function(role)
        role.set_node_visible(self.__protected_id, self.__protected_visible)
    end)
end

function ENode:__get_disabled()
    return self.__protected_disabled
end

function ENode:__set_disabled(value)
    self.__protected_disabled = value
    self:__update_disabled()
end

function ENode:__update_disabled()
    push(function(role)
        role.set_node_touch_enabled(self.__protected_id, not self.__protected_disabled)
    end)
end

---@param event string
---@param callback fun(data: {role: Role, target: UIManager.ENode, listener: UIManager.Listener})
---@return UIManager.Listener
function ENode:listen(event, callback)
    local listener = Listener:new()
    local handler = event_handlers[event]
    local trigger
    if not handler then
        event_handlers[event] = {}
        handler = event_handlers[event]

        ---@param data {eui_node_id: ENode, role: Role}
        local ok, registered_trigger = host_events.register_custom_event(event, function(_, _, data)
            local handler_data = event_handlers[event][data.eui_node_id]
            if handler_data and handler_data.callbacks and not handler_data.node._disabled then
                context.client_role = data.role
                for _, cb in ipairs(handler_data.callbacks) do
                    cb({
                        role = data.role,
                        target = handler_data.node,
                        listener = listener
                    })
                end
                context.client_role = nil
            end
        end)
        trigger = ok and registered_trigger or nil
        handler.trigger = trigger
    end

    local handler_data = handler[self.__protected_id]
    if not handler_data then
        handler[self.__protected_id] = {
            callbacks = { callback },
            node = self
        }
    else
        table.insert(handler_data.callbacks, callback)
    end

    -- 设置 listener 的相关信息，用于后续删除
    listener._event = event
    listener._callback = callback
    listener._node_id = self.__protected_id

    return listener
end

return ENode

