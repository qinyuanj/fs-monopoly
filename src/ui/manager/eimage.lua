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

function EImage:set_texture_keep_size(image_key)
    self.__protected_image_texture = image_key
    self:__apply_image_texture(false)
end

function EImage:set_texture_native_size(image_key)
    self.__protected_image_texture = image_key
    self:__apply_image_texture(true)
end

return EImage

--[[ mutate4lua-manifest
version=4
projectHash=305ba4d76783ee57
scope.0.id=chunk:src/ui/manager/eimage.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=82
scope.0.semanticHash=503c141bbd7ba380
scope.1.id=function:EImage:init
scope.1.kind=function
scope.1.startLine=16
scope.1.endLine=21
scope.1.semanticHash=4e61c028e3257dd6
scope.2.id=function:EImage:__get_image_color
scope.2.kind=function
scope.2.startLine=23
scope.2.endLine=25
scope.2.semanticHash=c0484ae42c9068b0
scope.3.id=function:EImage:__set_image_color
scope.3.kind=function
scope.3.startLine=27
scope.3.endLine=30
scope.3.semanticHash=d9865bc65df52544
scope.4.id=function:EImage:__update_image_color
scope.4.kind=function
scope.4.startLine=32
scope.4.endLine=36
scope.4.semanticHash=1769398f7a96b855
scope.5.id=function:<anonymous>
scope.5.kind=function
scope.5.startLine=33
scope.5.endLine=35
scope.5.semanticHash=af10c7ccfb55253d
scope.6.id=function:EImage:__get_image_texture
scope.6.kind=function
scope.6.startLine=38
scope.6.endLine=40
scope.6.semanticHash=c0484ae42c9068b0
scope.7.id=function:EImage:__set_image_texture
scope.7.kind=function
scope.7.startLine=42
scope.7.endLine=45
scope.7.semanticHash=d9865bc65df52544
scope.8.id=function:EImage:__update_image_texture
scope.8.kind=function
scope.8.startLine=47
scope.8.endLine=49
scope.8.semanticHash=f89eb88f0ef854b4
scope.9.id=function:EImage:__apply_image_texture
scope.9.kind=function
scope.9.startLine=51
scope.9.endLine=57
scope.9.semanticHash=a1b8a5225fa660a3
scope.10.id=function:<anonymous>#2
scope.10.kind=function
scope.10.startLine=53
scope.10.endLine=56
scope.10.semanticHash=2723d7b50130ebb8
scope.11.id=function:EImage:__get_transition_time
scope.11.kind=function
scope.11.startLine=59
scope.11.endLine=61
scope.11.semanticHash=c0484ae42c9068b0
scope.12.id=function:EImage:__set_transition_time
scope.12.kind=function
scope.12.startLine=63
scope.12.endLine=65
scope.12.semanticHash=018f9c51ceaf9c9c
scope.13.id=function:EImage:set_texture_keep_size
scope.13.kind=function
scope.13.startLine=67
scope.13.endLine=70
scope.13.semanticHash=ad0efaf86a556be9
scope.14.id=function:EImage:set_texture_native_size
scope.14.kind=function
scope.14.startLine=72
scope.14.endLine=75
scope.14.semanticHash=ad0efaf86a556be9
scope.15.id=function:EImage:reset_size
scope.15.kind=function
scope.15.startLine=77
scope.15.endLine=79
scope.15.semanticHash=f89eb88f0ef854b4
]]
