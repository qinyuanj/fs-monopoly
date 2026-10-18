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

--[[ mutate4lua-manifest
version=4
projectHash=f35fe439fd46d5f6
scope.0.id=chunk:src/ui/screens/skin_panel/skin_gallery.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=88
scope.0.semanticHash=0cc785e07831fbaf
scope.1.id=function:_clear_legacy_fields
scope.1.kind=function
scope.1.startLine=11
scope.1.endLine=17
scope.1.semanticHash=3b17c050d1eb323e
scope.2.id=function:_is_panel_open
scope.2.kind=function
scope.2.startLine=19
scope.2.endLine=23
scope.2.semanticHash=6e85fe784e216784
scope.3.id=function:_ensure_route_state
scope.3.kind=function
scope.3.startLine=25
scope.3.endLine=34
scope.3.semanticHash=7d1522e8fa7ef2ef
scope.4.id=function:_set_mode
scope.4.kind=function
scope.4.startLine=36
scope.4.endLine=40
scope.4.semanticHash=9adef315c32e0290
scope.5.id=function:skin_gallery.open_skin
scope.5.kind=function
scope.5.startLine=42
scope.5.endLine=46
scope.5.semanticHash=bae4d1777dbb1f64
scope.6.id=function:skin_gallery.open_gallery
scope.6.kind=function
scope.6.startLine=48
scope.6.endLine=52
scope.6.semanticHash=bae4d1777dbb1f64
scope.7.id=function:_close
scope.7.kind=function
scope.7.startLine=54
scope.7.endLine=60
scope.7.semanticHash=3469466021815093
scope.8.id=function:_unlock_current
scope.8.kind=function
scope.8.startLine=62
scope.8.endLine=66
scope.8.semanticHash=0e307e772fbd218e
scope.9.id=function:_equip_current
scope.9.kind=function
scope.9.startLine=68
scope.9.endLine=72
scope.9.semanticHash=7bc761cabf6ac284
scope.10.id=function:skin_gallery.handle_action
scope.10.kind=function
scope.10.startLine=74
scope.10.endLine=85
scope.10.semanticHash=e6ab9b7a7d087361
]]
