local nodes = require("src.ui.schema.skin")
local runtime_assets = require("src.config.runtime_assets")
local ui_controls = require("src.ui.render.support.ui_controls")

local M = {}

local function _refresh_card_frame(ui, slot, visible)
  local frame_name = nodes.card_frames[slot]
  if not frame_name then
    return
  end
  ui_controls.set_control_state(ui, frame_name, { visible = visible, touch_enabled = false })
end

local function _refresh_card_outline_container(ui, slot, visible)
  local outline_name = nodes.card_outlines[slot]
  if not outline_name then
    return
  end
  if ui.set_visible then
    ui:set_visible(outline_name, visible)
  end
  if ui.set_touch_enabled then
    ui:set_touch_enabled(outline_name, false)
  end
end

local function _set_matched_textures(runtime, card_name, image_key)
  local ok_qn, matched_nodes = pcall(runtime.query_nodes, card_name)
  if ok_qn and type(matched_nodes) == "table" then
    for _, node in ipairs(matched_nodes) do
      runtime.set_node_texture_keep_size(node, image_key)
    end
  end
end

local function _set_card_texture(runtime, card_name, image_key)
  if type(runtime.query_nodes) == "function" then
    _set_matched_textures(runtime, card_name, image_key)
  elseif type(runtime.query_node) == "function" then
    local node = runtime.query_node(card_name)
    if node then
      runtime.set_node_texture_keep_size(node, image_key)
    end
  end
end

local function _skin_card_image_key(state, skin)
  if skin == nil then
    return nil
  end
  local image = runtime_assets.image_for_skin_card(skin.product_id, runtime_assets.asset_context(state))
  if image.ok == true then
    return image.image_key
  end
  return nil
end

local function _set_card_image_state(ui, card_name, visible)
  if ui.set_visible then
    ui:set_visible(card_name, visible)
  end
  if ui.set_touch_enabled then
    ui:set_touch_enabled(card_name, visible)
  end
end

local function _refresh_card_image(state, ui, runtime, slot, skin)
  local card_name = nodes.card_images[slot]
  if not card_name then
    return
  end
  local image_key = _skin_card_image_key(state, skin)
  if image_key ~= nil then
    _set_card_texture(runtime, card_name, image_key)
  end
  _set_card_image_state(ui, card_name, skin ~= nil)
end

local function _refresh_price_icon(ui, slot, view)
  local price_icon = nodes.price_icons[slot]
  if not price_icon or not ui.set_visible then
    return
  end
  ui:set_visible(price_icon, view and view.price_icon_visible == true)
  if ui.set_touch_enabled then
    ui:set_touch_enabled(price_icon, false)
  end
end

function M.refresh_slot_visuals(state, ui, runtime, slot, view)
  local skin = view and view.skin or nil
  local has_skin = view and view.has_skin == true
  _refresh_card_frame(ui, slot, has_skin)
  _refresh_card_image(state, ui, runtime, slot, skin)
  _refresh_price_icon(ui, slot, view)
  _refresh_card_outline_container(ui, slot, has_skin)
end

return M

