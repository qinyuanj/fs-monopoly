local specs = require("src.ui.render.status3d.specs")
local scene = require("src.ui.render.status3d.scene")
local resolve = require("src.ui.render.status3d.status_resolve")

local M = {}

local _remaining_text_cache = {}
local _remaining_text_prefix = "剩余回合："

local function _get_remaining_text(remaining)
  local text = _remaining_text_cache[remaining]
  if text == nil then
    text = _remaining_text_prefix .. tostring(remaining)
    _remaining_text_cache[remaining] = text
  end
  return text
end

local function _text_node(cache, player, status_key)
  return cache.text_nodes[player.id] and cache.text_nodes[player.id][status_key]
end

local function _resolve_text_status_context(cache, player, status_key, game)
  local spec = specs.status_specs[status_key]
  if not (spec and spec.text_node_name) then
    return nil, nil
  end
  local remaining = resolve.resolve_remaining_value(game, player, spec.remaining_field)
  local text_node = _text_node(cache, player, status_key)
  if remaining <= 0 or text_node == nil then
    return nil, nil
  end
  return remaining, text_node
end

local function _sync_text_status(cache, player, status_key, roles, game)
  local remaining, text_node = _resolve_text_status_context(cache, player, status_key, game)
  if remaining == nil then
    return
  end
  local text = _get_remaining_text(remaining)
  for _, role in ipairs(roles) do
    -- ipairs 遇 nil 即停,role 恒非 nil,`role and` 是死防御(#262 删除:
    -- and->or 在 role 恒真下逐值等价)。
    if role.set_label_text then
      pcall(role.set_label_text, text_node, text)
    end
  end
end

local function _apply_layer_visibility(player_layers, roles, status_key, deps)
  for _, key in ipairs(specs.status_priority) do
    local layer = player_layers[key]
    if layer then
      scene.set_layer_visible_for_roles(layer, roles, status_key == key, deps)
    end
  end
end

function M.sync_layer_status(cache, player, status_key, deps, game)
  local player_id = player.id
  local player_layers = cache.layers[player_id]
  if not player_layers then
    return
  end
  local roles = scene.resolve_observer_roles()
  if cache.last_status_key_by_player[player_id] == status_key then
    _sync_text_status(cache, player, status_key, roles, game)
    return
  end
  _apply_layer_visibility(player_layers, roles, status_key, deps)
  _sync_text_status(cache, player, status_key, roles, game)
  cache.last_status_key_by_player[player_id] = status_key
end

-- Status-key resolution lives in status_resolve; re-exported here so existing
-- callers (init.lua, behavior specs) keep a single status entry point.
M.resolve_player_status_key = resolve.resolve_player_status_key

return M

