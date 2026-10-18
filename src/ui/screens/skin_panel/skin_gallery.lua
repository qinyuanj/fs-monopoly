local skin_panel = require("src.ui.screens.skin_panel")
local item_atlas = require("src.ui.screens.item_atlas")

local skin_gallery = {}

local _panel_routes = {
  skin = { state_key = "skin_panel", target = skin_panel },
  gallery = { state_key = "item_atlas", target = item_atlas },
}

local function _is_panel_open(ui, mode)
  local panel_route = _panel_routes[mode]
  local panel_state = panel_route and ui[panel_route.state_key] or nil
  return panel_state ~= nil and panel_state.open == true
end

local function _ensure_route_state(state)
  local ui = assert(assert(state, "missing state").ui, "missing state.ui")
  ui.skin_gallery = ui.skin_gallery or {}
  local route = ui.skin_gallery
  if not _is_panel_open(ui, route.mode) then
    route.mode = nil
  end
  return route
end

local function _set_mode(state, mode)
  local route = _ensure_route_state(state)
  route.mode = mode
  return route
end

function skin_gallery.open_skin(state, role_id)
  local panel = skin_panel.open(state, role_id)
  _set_mode(state, panel.open == true and "skin" or nil)
  return panel
end

function skin_gallery.open_gallery(state, role_id)
  local atlas = item_atlas.open(state, role_id)
  _set_mode(state, atlas.open == true and "gallery" or nil)
  return atlas
end

local function _close(state)
  local route = _ensure_route_state(state)
  local panel_route = _panel_routes[route.mode]
  local panel = panel_route and panel_route.target.close(state) or nil
  route.mode = nil
  return panel or route
end

local function _unlock_current(state, role_id, source)
  local panel = skin_panel.unlock(state, role_id, source, 1)
  _set_mode(state, panel.open == true and "skin" or nil)
  return panel
end

local function _equip_current(state, role_id)
  local panel = skin_panel.equip(state, role_id, 1)
  _set_mode(state, panel.open == true and "skin" or nil)
  return panel
end

function skin_gallery.handle_action(state, action, role_id)
  if action == "close" then
    return _close(state)
  end
  if action == "buy" or action == "gift" then
    return _unlock_current(state, role_id, action)
  end
  if action == "equip" then
    return _equip_current(state, role_id)
  end
  return _ensure_route_state(state)
end

return skin_gallery

