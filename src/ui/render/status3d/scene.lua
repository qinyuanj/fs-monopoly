local meta = require("src.ui.render.status3d.meta")
local specs = require("src.ui.render.status3d.specs")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local host_runtime_resolver = require("src.ui.render.support.host_runtime_resolver")

local M = {}

local _empty_roles = {}

local _resolve_host_runtime = host_runtime_resolver.from_deps

local function _resolve_role(player_id, deps)
  local host_runtime = _resolve_host_runtime(deps)
  return host_runtime.resolve_role_with(player_id, function(role)
    return type(role.get_ctrl_unit) == "function"
  end)
end

local function _resolve_observer_roles()
  local roles = runtime_ports.resolve_roles()
  if type(roles) == "table" then
    return roles
  end
  return _empty_roles
end

local function _set_layer_visible_for_roles(layer, roles, visible, deps)
  local host_runtime = _resolve_host_runtime(deps)
  if not host_runtime.has_scene_ui_support() then
    return
  end
  for _, role in ipairs(roles) do
    if role ~= nil then
      host_runtime.set_scene_ui_visible(layer, role, visible)
    end
  end
end

local function _create_scene_ui_bind_unit(ctrl_unit, layout_id)
  local offset = math.Vector3(0.0, 4.0, 0.0)
  if ctrl_unit and ctrl_unit.create_scene_ui_bind_unit then
    return ctrl_unit.create_scene_ui_bind_unit(layout_id, Enums.ModelSocket.socket_head, offset, -1.0, true, true)
  end
  return nil
end

local function _resolve_label_node_id(node_name)
  -- node_name 来自静态 specs.text_node_name(恒为非空字符串),串守卫是死防御
  -- (#262 删除:or->and 与 ""->nil 在配置约束输入下不可观测)。
  if not (UIManager and type(UIManager.get_first_node_by_name) == "function") then
    return nil
  end
  local ui_node = UIManager.get_first_node_by_name(node_name)
  if ui_node == nil then
    return nil
  end
  return ui_node.id
end

local function _resolve_text_node(layer, status_key, deps)
  -- status_key 恒为 status_specs 的键(来自 meta.layouts),spec 与
  -- text_node_name 静态恒在,and->or 不可观测,守卫删除(#262)。
  local node_id = _resolve_label_node_id(specs.status_specs[status_key].text_node_name)
  if node_id == nil then
    return nil
  end
  local host_runtime = _resolve_host_runtime(deps)
  if type(host_runtime.get_eui_node_at_scene_ui) ~= "function" then
    return nil
  end
  return host_runtime.get_eui_node_at_scene_ui(layer, node_id)
end

local function _resolve_ctrl_unit_for_player(cache, player_id, deps)
  local role = _resolve_role(player_id, deps)
  if role == nil then
    meta.warn_once(cache, "missing_role_" .. tostring(player_id), "status3d missing role:", tostring(player_id))
    return nil
  end
  local ctrl_unit = role.get_ctrl_unit and role.get_ctrl_unit()
  if not (ctrl_unit and ctrl_unit.create_scene_ui_bind_unit) then
    meta.warn_once(cache, "missing_ctrl_unit_" .. tostring(player_id), "status3d unit missing create_scene_ui_bind_unit:", tostring(player_id))
    return nil
  end
  return ctrl_unit
end

local function _create_layer_for_status(ctrl_unit, cache, status_key, layout_id, player_id, player_layers, player_text_nodes, roles, deps)
  local layer = _create_scene_ui_bind_unit(ctrl_unit, layout_id)
  if layer == nil then
    meta.warn_once(cache, "create_layer_" .. tostring(status_key) .. "_" .. tostring(player_id),
      "status3d create layer failed:", tostring(status_key), tostring(player_id))
    return
  end
  player_layers[status_key] = layer
  _set_layer_visible_for_roles(layer, roles, false, deps)
  local text_node = _resolve_text_node(layer, status_key, deps)
  if text_node ~= nil then
    player_text_nodes[status_key] = text_node
  else
    meta.warn_once(cache, "missing_text_node_" .. tostring(status_key) .. "_" .. tostring(player_id),
      "status3d missing remaining-text node:", tostring(status_key), tostring(player_id))
  end
end

function M.ensure_layers_for_player(cache, player, deps)
  local player_id = player.id
  if cache.layers[player_id] ~= nil then
    return true
  end
  local ctrl_unit = _resolve_ctrl_unit_for_player(cache, player_id, deps)
  if ctrl_unit == nil then
    return false
  end
  local resolved_meta, err = meta.build_meta(cache)
  if not resolved_meta then
    meta.warn_once(cache, "meta_error", "status3d meta resolve failed:", tostring(err))
    cache.disabled = true
    return false
  end
  local player_layers = {}
  local player_text_nodes = {}
  local roles = _resolve_observer_roles()
  for status_key, layout_id in pairs(resolved_meta.layouts) do
    _create_layer_for_status(ctrl_unit, cache, status_key, layout_id, player_id, player_layers, player_text_nodes, roles, deps)
  end
  cache.layers[player_id] = player_layers
  cache.text_nodes[player_id] = player_text_nodes
  cache.last_status_key_by_player[player_id] = specs.INIT_STATUS
  return true
end

M.resolve_observer_roles = _resolve_observer_roles
M.set_layer_visible_for_roles = _set_layer_visible_for_roles

return M

