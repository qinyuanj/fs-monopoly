-- ui.manager.utils — UIManager 对外 facade 组装点。
-- 共享运行时状态落 context.lua(簇内子模块显式 require);本模块在 context 表上挂
-- 类、枚举与查询函数,组装成对外 UIManager 表并发布到 _G 供消费点(ui_bootstrap /
-- event_bindings / status3d / runtime_ui)使用。子模块之间已改显式 require,不再读全局。
---@class UIManager
local UIManager = require("src.ui.manager.context")

UIManager.ECanvas = require("src.ui.manager.ecanvas")
UIManager.ENode = require("src.ui.manager.enode")
UIManager.ELabel = require("src.ui.manager.elabel")
UIManager.EButton = require("src.ui.manager.ebutton")
UIManager.EImage = require("src.ui.manager.eimage")
UIManager.EProgressbar = require("src.ui.manager.eprogressbar")
UIManager.EInputField = require("src.ui.manager.einputfield")
UIManager.Builder = require("src.ui.manager.builder")
UIManager.Listener = require("src.ui.manager.listener")
UIManager.Array = require("src.ui.manager.array")
UIManager.ArrayReadOnly = require("src.ui.manager.array_read_only")

---@alias UIManager.ENodeUnion UIManager.ENode | UIManager.ELabel | UIManager.EImage | UIManager.EButton | UIManager.EProgressbar | UIManager.EInputField

---@enum UIManager.ENodeType
UIManager.ENodeType = {
    ELabel = "UIManager.ELabel",
    EButton = "UIManager.EButton",
    EImage = "UIManager.EImage",
    ENode = "UIManager.ENode",
}

---@param name string
---@return UIManager.ENodeUnion?
UIManager.get_first_node_by_name = function(name)
    return UIManager.name_node_mapping[name] and UIManager.name_node_mapping[name][1] or nil
end

---@param name string
---@return UIManager.ENodeUnion[]
UIManager.query_nodes_by_name = function(name)
    return UIManager.name_node_mapping[name] or {}
end

---@param id ENode
---@return UIManager.ENodeUnion?
UIManager.query_node_by_id = function(id)
    return UIManager.nodes_list[id]
end

---@enum UIManager.EVENT
UIManager.EVENT = {
    CLICK = "CLICK"
}

-- 发布对外 facade 到全局供消费点读取(单向 export,非簇内互引)。
_G["UIManager"] = UIManager

return UIManager

--[[ mutate4lua-manifest
version=4
projectHash=160594cb505b7a5a
scope.0.id=chunk:src/ui/manager/utils.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=65
scope.0.semanticHash=a92579c82cff9522
scope.1.id=function:UIManager.get_first_node_by_name
scope.1.kind=function
scope.1.startLine=32
scope.1.endLine=34
scope.1.semanticHash=0450ebb91ed6c1d1
scope.2.id=function:UIManager.query_nodes_by_name
scope.2.kind=function
scope.2.startLine=38
scope.2.endLine=40
scope.2.semanticHash=090df05bc74ca229
scope.3.id=function:UIManager.query_node_by_id
scope.3.kind=function
scope.3.startLine=44
scope.3.endLine=46
scope.3.semanticHash=3ed9a36b04f855c4
scope.4.id=function:UIManager.typeof
scope.4.kind=function
scope.4.startLine=57
scope.4.endLine=59
scope.4.semanticHash=59a634c03d1043c7
]]
