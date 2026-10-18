---@class UIManager.EButton : UIManager.ENode
---@field __name "UIManager.EButton"
---@field text string 按钮文本
---@field text_color Color 文本颜色，Hex值，例如0xFF0000是红色
---@field font_size Fixed 字体大小
---@field normal_image ImageKey 常态图片
---@field pressed_image ImageKey 按下图片
---@field protected __protected_text string 受保护的文本内容
---@field protected __protected_text_color Color 受保护的文本颜色
---@field protected __protected_font_size Fixed 受保护的字体大小
---@field protected __protected_normal_image ImageKey 常态图片
---@field protected __protected_pressed_image ImageKey 按下图片
local Class = require("src.ui.manager.class")
local ENode = require("src.ui.manager.enode")
local push = require("src.ui.manager.host_push").push
local EButton = Class("UIManager.EButton", ENode)

---@param node ENode
---@param name string
function EButton:init(node, name)
    ENode.init(self, node, name)
    self.__protected_text = ""
end

function EButton:__set_disabled(value)
    self.__protected_disabled = value
    self:__update_disabled()
end

function EButton:__update_disabled()
    -- 两个宿主方法按角色成对下发(touch 后 enabled),顺序与拆成两次 push 不同,故合在一个 apply 内。
    push(function(role)
        role.set_node_touch_enabled(self.__protected_id, not self.__protected_disabled)
        role.set_button_enabled(self.__protected_id, not self.__protected_disabled)
    end)
end

function EButton:__get_text()
    return self.__protected_text
end

function EButton:__set_text(value)
    self.__protected_text = value
    self:__update_text()
end

function EButton:__update_text()
    push(function(role)
        role.set_button_text(self.__protected_id, self.__protected_text)
    end)
end

function EButton:__get_text_color()
    return self.__protected_text_color
end

function EButton:__set_text_color(value)
    self.__protected_text_color = value
    self:__update_text_color()
end

function EButton:__update_text_color()
    push(function(role)
        role.set_button_text_color(self.__protected_id, self.__protected_text_color)
    end)
end

function EButton:__get_font_size()
    return self.__protected_font_size
end

function EButton:__set_font_size(value)
    self.__protected_font_size = math.tofixed(value)
    self:__update_font_size()
end

function EButton:__update_font_size()
    push(function(role)
        role.set_button_font_size(self.__protected_id, self.__protected_font_size)
    end)
end

return EButton

