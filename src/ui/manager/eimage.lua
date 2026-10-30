---@class UIManager.EImage : UIManager.ENode
---@field __name "UIManager.EImage"
---@field image_color Color 图片颜色
---@field image_texture ImageKey 图片预设
---@field transition_time Fixed 样式变化时间
---@field protected __protected_image_color Color 图片颜色
---@field protected __protected_image_texture ImageKey 图片预设
---@field protected __protected_transition_time Fixed 受保护的样式变化时间
local Class = require("src.ui.manager.class")
local ENode = require("src.ui.manager.enode")
local push = require("src.ui.manager.host_push").push
local EImage = Class("UIManager.EImage", ENode)

---@param node ENode
---@param name string
function EImage:init(node, name)
    ENode.init(self, node, name)
    self.__protected_image_color = 0xffffff
    self.__protected_image_texture = -1
    self.__protected_transition_time = 0.0
end

function EImage:__get_image_color()
    return self.__protected_image_color
end

function EImage:__set_image_color(value)
    self.__protected_image_color = value
    self:__update_image_color()
end

function EImage:__update_image_color()
    push(function(role)
        role.set_image_color(self.__protected_id, self.__protected_image_color, self.__protected_transition_time)
    end)
end

function EImage:__get_image_texture()
    return self.__protected_image_texture
end

function EImage:__set_image_texture(value)
    self.__protected_image_texture = value
    self:__update_image_texture()
end

function EImage:__update_image_texture()
    self:__apply_image_texture(false)
end

function EImage:__apply_image_texture(reset_size)
    local should_reset_size = reset_size == true
    push(function(role)
        role.set_image_texture_by_key_with_auto_resize(self.__protected_id, self.__protected_image_texture,
            should_reset_size)
    end)
end

function EImage:__get_transition_time()
    return self.__protected_transition_time
end

function EImage:__set_transition_time(value)
    self.__protected_transition_time = math.tofixed(value)
end

local function _set_texture(self, image_key, reset_size)
    self.__protected_image_texture = image_key
    self:__apply_image_texture(reset_size)
end

function EImage:set_texture_keep_size(image_key)
    _set_texture(self, image_key, false)
end

function EImage:set_texture_native_size(image_key)
    _set_texture(self, image_key, true)
end

return EImage

