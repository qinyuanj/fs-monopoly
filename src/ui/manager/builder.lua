---@class UIManager.Builder : Class
local Class = require("src.ui.manager.class")
local context = require("src.ui.manager.context")
local Builder = Class("UIManager.Builder")
local nodes_list = context.nodes_list
local name_node_mapping = context.name_node_mapping

-- 动态 dispatch 注册表:替代旧 `UIManager[buildType]` 的全局互引。
-- 键与旧 facade 上的节点类字段名一致;未登记的 buildType(如 Data 中的 "EAnimation")
-- 落 nil,由 build_node 回退到 ENode,与旧行为一致。
local node_classes = {
    ECanvas = require("src.ui.manager.ecanvas"),
    ENode = require("src.ui.manager.enode"),
    ELabel = require("src.ui.manager.elabel"),
    EButton = require("src.ui.manager.ebutton"),
    EImage = require("src.ui.manager.eimage"),
    EProgressbar = require("src.ui.manager.eprogressbar"),
    EInputField = require("src.ui.manager.einputfield"),
}

---@alias configName string
---@alias configType string

---@class BuilderConfig
---@field [1] configName 名称
---@field [2] configType 类型

---@async
---@param config_list table<ENode, BuilderConfig>
function Builder:init(config_list)
    if next(config_list) == nil then
        error("Empty config!")
    end
    context.config_list = config_list
    -- 第一阶段：创建所有节点，但不建立父子关系
    for id, config in pairs(config_list) do
        self:build_node(id, config)
    end

    -- 第二阶段：建立所有节点的父子关系
    for id, _ in pairs(config_list) do
        local node = nodes_list[id]
        if node then
            node:__init_children()
        end
    end
end

---@param id ENode
---@param config BuilderConfig
function Builder:build_node(id, config)
    if nodes_list[id] then
        return
    end
    local build_name = config[1]
    local build_type = config[2]
    local build_func = node_classes[build_type] --[[@as UIManager.ENode?]]
    local uinode
    if build_func then
        uinode = build_func:new(id, build_name)
    else
        uinode = node_classes.ENode:new(id, build_name)
    end

    local name_node = name_node_mapping[build_name]
    if not name_node then
        name_node_mapping[build_name] = { uinode }
    else
        table.insert(name_node, uinode)
    end
    nodes_list[id] = uinode
end

return Builder

