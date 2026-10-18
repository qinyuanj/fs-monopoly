local role_avatar = require("src.ui.view.role_avatar")
local runtime = require("src.ui.render.support.runtime_ui")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_assets = require("src.config.runtime_assets")

local M = {}

local function _payload_image_ref(payload)
  if payload == nil then
    return nil
  end
  return payload.image_ref
end

local function _payload_image_key(payload)
  if payload == nil then
    return nil
  end
  if payload.image_key ~= nil then
    return payload.image_key
  end
  return nil
end

local function _image_result_key(image)
  return image.ok == true and image.image_key or nil
end

local function _resolve_popup_image_key(state, payload)
  local image_key = _payload_image_key(payload)
  if image_key ~= nil then
    return image_key
  end
  local image_ref = _payload_image_ref(payload)
  if image_ref == nil then
    return nil
  end
  local image = runtime_assets.image_for_popup_card(payload.kind, image_ref, runtime_assets.asset_context(state))
  return _image_result_key(image)
end

local function _dismiss_nodes(ui)
  local popup = ui and ui.popup_screen or nil
  if popup == nil then
    return nil
  end
  local nodes = popup.dismiss_nodes
  if type(nodes) ~= "table" then
    return nil
  end
  return nodes
end

function M.set_popup_dismiss_touch(ui, enabled)
  local nodes = _dismiss_nodes(ui)
  if nodes == nil then
    return
  end
  for _, name in ipairs(nodes) do
    ui:set_touch_enabled(name, enabled == true)
  end
end

local function _non_empty_field(payload, key)
  local value = payload and payload[key] or nil
  if value ~= nil and value ~= "" then
    return value
  end
  return nil
end

function M.resolve_bankruptcy_text(payload)
  local text = _non_empty_field(payload, "text")
  if text ~= nil then
    return text
  end
  local reason = _non_empty_field(payload, "reason")
  if reason ~= nil then
    return reason
  end
  local player_name = _non_empty_field(payload, "player_name")
  if player_name ~= nil then
    return player_name .. " 破产出局"
  end
  return "破产出局"
end

local function _avatar_from_payload(payload)
  local avatar_key = payload and payload.avatar_key or nil
  if avatar_key == nil then
    return nil
  end
  return role_avatar.sanitize_image_key(avatar_key)
end

local function _role_for_player(player_id)
  if not player_id then
    return nil
  end
  return runtime_ports.resolve_role(player_id)
end

local function _avatar_from_role(role)
  if role == nil then
    return nil
  end
  return role_avatar.resolve_from_role(role)
end

local function _resolve_bankruptcy_avatar_key(payload)
  if not payload then
    return nil
  end
  local avatar_key = _avatar_from_payload(payload)
  if avatar_key ~= nil then
    return avatar_key
  end
  return _avatar_from_role(_role_for_player(payload.player_id))
end

local function _apply_node_image(ui, node_name, node, image_key, empty_key, set_texture, show_when_empty)
  if image_key ~= nil then
    set_texture(node, image_key)
    ui:set_visible(node_name, true)
    return
  end
  if empty_key ~= nil then
    set_texture(node, empty_key)
    ui:set_visible(node_name, show_when_empty == true)
    return
  end
  ui:set_visible(node_name, false)
end

local function _apply_screen_image(state, screen, node_name, image_key, set_texture, show_when_empty)
  local ui = state and state.ui
  if not ui or not screen or not node_name then
    return
  end
  local empty_image = runtime_assets.empty_image(runtime_assets.asset_context(state))
  _apply_node_image(ui, node_name, ui.query_node(node_name), image_key, empty_image.image_key, set_texture, show_when_empty)
end

local function _ui_screen(state, key)
  local ui = state and state.ui or nil
  return ui and ui[key] or nil
end

function M.set_popup_card_image(state, payload)
  local popup = _ui_screen(state, "popup_screen")
  _apply_screen_image(state, popup, popup and popup.card or nil, _resolve_popup_image_key(state, payload), function(node, key)
    runtime.set_node_texture_keep_size(node, key)
  end, false)
end

function M.set_bankruptcy_avatar_image(state, payload)
  local screen = _ui_screen(state, "bankruptcy_screen")
  _apply_screen_image(state, screen, screen and screen.avatar or nil, _resolve_bankruptcy_avatar_key(payload), function(node, key)
    runtime.set_node_texture_native_size(node, key)
  end, true)
end

return M

