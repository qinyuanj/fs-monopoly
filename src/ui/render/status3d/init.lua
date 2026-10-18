local meta = require("src.ui.render.status3d.meta")
local scene = require("src.ui.render.status3d.scene")
local status = require("src.ui.render.status3d.status")
local host_runtime_resolver = require("src.ui.render.support.host_runtime_resolver")

local M = {}

local _resolve_host_runtime = host_runtime_resolver.from_state

local function _destroy_layer(host_runtime, layer)
  if layer ~= nil then
    host_runtime.destroy_scene_ui(layer)
  end
end

local function _destroy_cached_layers(cache, host_runtime)
  for _, player_layers in pairs(cache.layers or {}) do
    for _, layer in pairs(player_layers) do
      _destroy_layer(host_runtime, layer)
    end
  end
end

function M.reset(state, deps)
  if not state or not state.ui_status_3d then
    return
  end
  local host_runtime = _resolve_host_runtime(state, deps)
  _destroy_cached_layers(state.ui_status_3d, host_runtime)
  state.ui_status_3d = nil
end

local function _check_scene_ui_support(cache, host_runtime)
  if not host_runtime.has_scene_ui_support() then
    meta.warn_once(cache, "missing_gameapi", "status3d disabled: missing scene ui GameAPI methods")
    cache.disabled = true
    return false
  end
  return true
end

local function _scene_ui_env_ready()
  return Enums and Enums.ModelSocket and Enums.ModelSocket.socket_head and math and math.Vector3
end

local function _check_scene_ui_env(cache)
  if not _scene_ui_env_ready() then
    meta.warn_once(cache, "missing_sceneui_env", "status3d disabled: missing scene ui runtime")
    cache.disabled = true
    return false
  end
  return true
end

local function _check_meta_ready(cache)
  local _, err = meta.build_meta(cache)
  if err then
    meta.warn_once(cache, "meta_error", "status3d disabled: " .. tostring(err))
    cache.disabled = true
    return false
  end
  return true
end

local function _has_any_dirty(dirty)
  return dirty and (dirty.players or dirty.turn or dirty.any)
end

local function _has_missing_player_layer(cache, players)
  for _, player in ipairs(players or {}) do
    if cache.layers[player.id] == nil then
      return true
    end
  end
  return false
end

local function _should_skip_sync(cache, dirty, players)
  local has_dirty = _has_any_dirty(dirty)
  local has_missing_layer = _has_missing_player_layer(cache, players)
  return not has_dirty and not has_missing_layer
end

local function _scene_ready(cache, host_runtime)
  return _check_scene_ui_support(cache, host_runtime)
      and _check_scene_ui_env(cache)
      and _check_meta_ready(cache)
end

local function _ensure_all_player_layers(cache, players, deps)
  for _, player in ipairs(players or {}) do
    scene.ensure_layers_for_player(cache, player, deps)
  end
end

local function _sync_all_player_status(cache, game, players, deps)
  for _, player in ipairs(players or {}) do
    if cache.layers[player.id] ~= nil then
      status.sync_layer_status(cache, player, status.resolve_player_status_key(game, player), deps, game)
    end
  end
end

local function _sync_guard(cache, host_runtime, dirty, players)
  if cache.disabled then
    return false
  end
  if not _scene_ready(cache, host_runtime) then
    return false
  end
  return not _should_skip_sync(cache, dirty, players)
end

function M.sync(game, state, dirty, deps)
  if not game or not state then
    return
  end
  local host_runtime = _resolve_host_runtime(state, deps)
  local cache = meta.ensure_cache(state)
  if not _sync_guard(cache, host_runtime, dirty, game.players) then
    return
  end
  _ensure_all_player_layers(cache, game.players, deps)
  _sync_all_player_status(cache, game, game.players, deps)
end

return M

