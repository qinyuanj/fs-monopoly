---@class UIManager.EInputField : UIManager.ENode
---@field __name "UIManager.EInputField"
---@field text string 文本内容
---@field text_color Color 文本颜色，Hex值，例如0xFF0000是红色
---@field protected __protected_text string 受保护的文本内容
local Class = require("src.ui.manager.class")
local ENode = require("src.ui.manager.enode")
local push = require("src.ui.manager.host_push").push
local EInputField = Class("UIManager.EInputField", ENode)

---@param node ENode
---@param name string
function EInputField:init(node, name)
    ENode.init(self, node, name)
    self.__protected_text = ""
end

function EInputField:__get_text()
    return self.__protected_text
end

function EInputField:__set_text(value)
    self.__protected_text = value
    self:__update_text()
end

function EInputField:__update_text()
    push(function(role)
        role.set_input_field_text(self.__protected_id, self.__protected_text)
    end)
end

return EInputField

