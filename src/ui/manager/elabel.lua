---@class UIManager.ELabel : UIManager.ENode
---@field __name "UIManager.ELabel"
---@field text string 文本内容
---@field label_background_color Color 背景颜色
---@field label_background_opacity Fixed 背景不透明度
---@field text_color Color 文本颜色，Hex值，例如0xFF0000是红色
---@field transition_time Fixed 样式变化时间
---@field font_family FontKey 字体
---@field font_size integer 字体大小
---@field outline_color Color 描边颜色
---@field outline boolean 是否描边
---@field outline_opacity Fixed 描边不透明度
---@field outline_width Fixed 描边宽度
---@field shadow_color Color 阴影颜色
---@field shadow boolean 是否阴影
---@field shadow_x_offset Fixed 阴影x偏移
---@field shadow_y_offset Fixed 阴影y偏移
---@field protected __protected_text string 受保护的文本内容
---@field protected __protected_label_background_color Color 背景颜色
---@field protected __protected_label_background_opacity Fixed 背景不透明度
---@field protected __protected_text_color Color 受保护的文本颜色
---@field protected __protected_transition_time Fixed 受保护的样式变化时间
---@field protected __protected_font_family FontKey 字体
---@field protected __protected_font_size integer 字体大小
---@field protected __protected_outline_color Color 描边颜色
---@field protected __protected_outline boolean 是否描边
---@field protected __protected_outline_opacity Fixed 描边不透明度
---@field protected __protected_outline_width Fixed 描边宽度
---@field protected __protected_shadow_color Color 阴影颜色
---@field protected __protected_shadow boolean 是否阴影
---@field protected __protected_shadow_x_offset Fixed 阴影x偏移
---@field protected __protected_shadow_y_offset Fixed 阴影y偏移
local Class = require("src.ui.manager.class")
local ENode = require("src.ui.manager.enode")
local push = require("src.ui.manager.host_push").push
local ELabel = Class("UIManager.ELabel", ENode)

---@param node ENode
---@param name string
function ELabel:init(node, name)
    ENode.init(self, node, name)
    self.__protected_text = ""
    self.__protected_transition_time = 0.0
end

function ELabel:__get_text()
    return self.__protected_text
end

function ELabel:__set_text(value)
    self.__protected_text = value
    self:__update_text()
end

function ELabel:__update_text()
    push(function(role)
        role.set_label_text(self.__protected_id, self.__protected_text)
    end)
end

function ELabel:__get_label_background_color()
    return self.__protected_label_background_color
end

function ELabel:__set_label_background_color(value)
    self.__protected_label_background_color = value
    self:__update_label_background_color()
end

function ELabel:__update_label_background_color()
    push(function(role)
        role.set_label_background_color(self.__protected_id, self.__protected_label_background_color,
            self.__protected_transition_time)
    end)
end

function ELabel:__get_label_background_opacity()
    return self.__protected_label_background_opacity
end

function ELabel:__set_label_background_opacity(value)
    self.__protected_label_background_opacity = math.tofixed(value)
    self:__update_label_background_opacity()
end

function ELabel:__update_label_background_opacity()
    push(function(role)
        role.set_label_background_opacity(self.__protected_id, self.__protected_label_background_opacity,
            self.__protected_transition_time)
    end)
end

function ELabel:__get_text_color()
    return self.__protected_text_color
end

function ELabel:__set_text_color(value)
    self.__protected_text_color = value
    self:__update_text_color()
end

function ELabel:__update_text_color()
    push(function(role)
        role.set_label_color(self.__protected_id, self.__protected_text_color, self.__protected_transition_time)
    end)
end

function ELabel:__get_transition_time()
    return self.__protected_transition_time
end

function ELabel:__set_transition_time(value)
    self.__protected_transition_time = math.tofixed(value)
end

function ELabel:__get_font_family()
    return self.__protected_font_family
end

function ELabel:__set_font_family(value)
    self.__protected_font_family = value
    self:__update_font_family()
end

function ELabel:__update_font_family()
    push(function(role)
        role.set_label_font(self.__protected_id, self.__protected_font_family)
    end)
end

function ELabel:__get_font_size()
    return self.__protected_font_size
end

function ELabel:__set_font_size(value)
    self.__protected_font_size = math.tointeger(value)
    self:__update_font_size()
end

function ELabel:__update_font_size()
    push(function(role)
        role.set_label_font_size(self.__protected_id, self.__protected_font_size, self.__protected_transition_time)
    end)
end

function ELabel:__get_outline_color()
    return self.__protected_outline_color
end

function ELabel:__set_outline_color(value)
    self.__protected_outline_color = value
    self:__update_outline_color()
end

function ELabel:__update_outline_color()
    push(function(role)
        role.set_label_outline_color(self.__protected_id, self.__protected_outline_color)
    end)
end

function ELabel:__get_outline()
    return self.__protected_outline
end

function ELabel:__set_outline(value)
    self.__protected_outline = value
    self:__update_outline()
end

function ELabel:__update_outline()
    push(function(role)
        role.set_label_outline_enabled(self.__protected_id, self.__protected_outline)
    end)
end

function ELabel:__get_outline_opacity()
    return self.__protected_outline_opacity
end

function ELabel:__set_outline_opacity(value)
    self.__protected_outline_opacity = math.tofixed(value)
    self:__update_outline_opacity()
end

function ELabel:__update_outline_opacity()
    push(function(role)
        role.set_label_outline_opacity(self.__protected_id, self.__protected_outline_opacity)
    end)
end

function ELabel:__get_outline_width()
    return self.__protected_outline_width
end

function ELabel:__set_outline_width(value)
    self.__protected_outline_width = math.tofixed(value)
    self:__update_outline_width()
end

function ELabel:__update_outline_width()
    push(function(role)
        role.set_label_outline_width(self.__protected_id, self.__protected_outline_width)
    end)
end

function ELabel:__get_shadow_color()
    return self.__protected_shadow_color
end

function ELabel:__set_shadow_color(value)
    self.__protected_shadow_color = value
    self:__update_shadow_color()
end

function ELabel:__update_shadow_color()
    push(function(role)
        role.set_label_shadow_color(self.__protected_id, self.__protected_shadow_color)
    end)
end

function ELabel:__get_shadow()
    return self.__protected_shadow
end

function ELabel:__set_shadow(value)
    self.__protected_shadow = value
    self:__update_shadow()
end

function ELabel:__update_shadow()
    push(function(role)
        role.set_label_shadow_enabled(self.__protected_id, self.__protected_shadow)
    end)
end

function ELabel:__get_shadow_x_offset()
    return self.__protected_shadow_x_offset
end

function ELabel:__set_shadow_x_offset(value)
    self.__protected_shadow_x_offset = math.tofixed(value)
    self:__update_shadow_x_offset()
end

function ELabel:__update_shadow_x_offset()
    push(function(role)
        role.set_label_shadow_x_offset(self.__protected_id, self.__protected_shadow_x_offset)
    end)
end

function ELabel:__get_shadow_y_offset()
    return self.__protected_shadow_y_offset
end

function ELabel:__set_shadow_y_offset(value)
    self.__protected_shadow_y_offset = math.tofixed(value)
    self:__update_shadow_y_offset()
end

function ELabel:__update_shadow_y_offset()
    push(function(role)
        role.set_label_shadow_y_offset(self.__protected_id, self.__protected_shadow_y_offset)
    end)
end

return ELabel

