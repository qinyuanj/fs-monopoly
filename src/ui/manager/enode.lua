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

--[[ mutate4lua-manifest
version=4
projectHash=4903cde5b2f074ff
scope.0.id=chunk:src/ui/manager/enode.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=308
scope.0.semanticHash=5d95db1f47cf9d08
scope.1.id=function:query_node_by_id
scope.1.kind=function
scope.1.startLine=34
scope.1.endLine=36
scope.1.semanticHash=fc8eda1d7903d2b1
scope.2.id=function:ENode.__custom_index
scope.2.kind=function
scope.2.startLine=38
scope.2.endLine=55
scope.2.semanticHash=bad5d3ef42a8f888
scope.3.id=function:ENode.__new_custom_index
scope.3.kind=function
scope.3.startLine=57
scope.3.endLine=74
scope.3.semanticHash=417c23dde5376ec8
scope.4.id=function:ENode:init
scope.4.kind=function
scope.4.startLine=78
scope.4.endLine=93
scope.4.semanticHash=8733e9f1f43a3bf5
scope.5.id=function:ENode:__init_children
scope.5.kind=function
scope.5.startLine=95
scope.5.endLine=101
scope.5.semanticHash=6c699043b1949529
scope.6.id=function:ENode:__get_children
scope.6.kind=function
scope.6.startLine=103
scope.6.endLine=105
scope.6.semanticHash=c0484ae42c9068b0
scope.7.id=function:ENode:__set_children
scope.7.kind=function
scope.7.startLine=107
scope.7.endLine=109
scope.7.semanticHash=95e19093d3c9cec2
scope.8.id=function:ENode:__get_custom_data
scope.8.kind=function
scope.8.startLine=111
scope.8.endLine=113
scope.8.semanticHash=c0484ae42c9068b0
scope.9.id=function:ENode:__set_custom_data
scope.9.kind=function
scope.9.startLine=115
scope.9.endLine=117
scope.9.semanticHash=e66f374cdcfa7616
scope.10.id=function:ENode:__get_parent
scope.10.kind=function
scope.10.startLine=119
scope.10.endLine=121
scope.10.semanticHash=c0484ae42c9068b0
scope.11.id=function:ENode:__set_parent
scope.11.kind=function
scope.11.startLine=123
scope.11.endLine=125
scope.11.semanticHash=95e19093d3c9cec2
scope.12.id=function:ENode:__get_name
scope.12.kind=function
scope.12.startLine=127
scope.12.endLine=129
scope.12.semanticHash=c0484ae42c9068b0
scope.13.id=function:ENode:__set_name
scope.13.kind=function
scope.13.startLine=131
scope.13.endLine=133
scope.13.semanticHash=95e19093d3c9cec2
scope.14.id=function:ENode:__get_id
scope.14.kind=function
scope.14.startLine=135
scope.14.endLine=137
scope.14.semanticHash=c0484ae42c9068b0
scope.15.id=function:ENode:__set_id
scope.15.kind=function
scope.15.startLine=139
scope.15.endLine=141
scope.15.semanticHash=95e19093d3c9cec2
scope.16.id=function:ENode:__get_visible
scope.16.kind=function
scope.16.startLine=143
scope.16.endLine=145
scope.16.semanticHash=c0484ae42c9068b0
scope.17.id=function:ENode:__set_visible
scope.17.kind=function
scope.17.startLine=147
scope.17.endLine=150
scope.17.semanticHash=d9865bc65df52544
scope.18.id=function:ENode:__update_visible
scope.18.kind=function
scope.18.startLine=152
scope.18.endLine=156
scope.18.semanticHash=83f74b98acb97bad
scope.19.id=function:<anonymous>
scope.19.kind=function
scope.19.startLine=153
scope.19.endLine=155
scope.19.semanticHash=713e373fad31bfcb
scope.20.id=function:ENode:__get_disabled
scope.20.kind=function
scope.20.startLine=158
scope.20.endLine=160
scope.20.semanticHash=c0484ae42c9068b0
scope.21.id=function:ENode:__set_disabled
scope.21.kind=function
scope.21.startLine=162
scope.21.endLine=165
scope.21.semanticHash=d9865bc65df52544
scope.22.id=function:ENode:__update_disabled
scope.22.kind=function
scope.22.startLine=167
scope.22.endLine=171
scope.22.semanticHash=9a8b358fdf145079
scope.23.id=function:<anonymous>#2
scope.23.kind=function
scope.23.startLine=168
scope.23.endLine=170
scope.23.semanticHash=8a2db6fbedbbd8f9
scope.24.id=function:ENode:get_first_node_by_name
scope.24.kind=function
scope.24.startLine=175
scope.24.endLine=179
scope.24.semanticHash=d64d5e55c9273477
scope.25.id=function:ENode:query_nodes_by_name
scope.25.kind=function
scope.25.startLine=183
scope.25.endLine=191
scope.25.semanticHash=701f20ddd925e6c4
scope.26.id=function:<anonymous>#3
scope.26.kind=function
scope.26.startLine=185
scope.26.endLine=189
scope.26.semanticHash=c70104a9b65bc24a
scope.27.id=function:ENode:get_first_node_by_name_dfs
scope.27.kind=function
scope.27.startLine=195
scope.27.endLine=208
scope.27.semanticHash=7c109ae616f13695
scope.28.id=function:ENode:query_nodes_by_name_dfs
scope.28.kind=function
scope.28.startLine=212
scope.28.endLine=233
scope.28.semanticHash=ed8523ef54376176
scope.29.id=function:dfs
scope.29.kind=function
scope.29.startLine=216
scope.29.endLine=230
scope.29.semanticHash=3353669ba179e039
scope.30.id=function:ENode:for_all_roles
scope.30.kind=function
scope.30.startLine=238
scope.30.endLine=245
scope.30.semanticHash=60bb5996369e920b
scope.31.id=function:ENode:set_attribute
scope.31.kind=function
scope.31.startLine=249
scope.31.endLine=251
scope.31.semanticHash=4218fa0408531805
scope.32.id=function:ENode:get_attribtue
scope.32.kind=function
scope.32.startLine=255
scope.32.endLine=257
scope.32.semanticHash=70ade069282003e1
scope.33.id=function:ENode:listen
scope.33.kind=function
scope.33.startLine=262
scope.33.endLine=305
scope.33.semanticHash=29cfb8a1630b8f99
scope.34.id=function:<anonymous>#4
scope.34.kind=function
scope.34.startLine=271
scope.34.endLine=284
scope.34.semanticHash=17a886d322d73804
]]
