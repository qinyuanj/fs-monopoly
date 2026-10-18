local building_effects = require("src.ui.render.board.building_effects")
local tile_renderer = require("src.ui.render.board.tile")
local runtime_constants = require("src.config.gameplay.runtime_constants")
local contiguous_count = require("src.ui.view.contiguous_count")
local tile_rent = require("src.ui.view.tile_rent")
local shared = require("src.ui.render.board.visual_sync_shared")
local tables = require("src.foundation.tables")

local visual_sync_tile = {}

local function _scene_tiles(scene)
  return scene and scene.tiles or nil
end

local function _resolve_tile_unit(state, scene, idx)
  local tile_units = state and state.tile_units or nil
  local from_state = tables.at(tile_units, idx)
  if from_state ~= nil then
    return from_state
  end
  return tables.at(_scene_tiles(scene), idx)
end

local function _resolve_contiguous_rent(board, tile_id, owner_id)
  if owner_id == nil or board == nil then
    return nil
  end
  local rents = contiguous_count.build_rent_for_owner(board, owner_id, function(tile)
    return tile_rent.for_level(tile, tile and tile.level or 0)
  end)
  local rent = rents[tile_id]
  if rent and rent > 0 then
    return rent
  end
  return nil
end

local function _game_of(state)
  return state and state.game or nil
end

local function _find_player_by_id(game, owner_id)
  if game and type(game.find_player_by_id) == "function" then
    return game:find_player_by_id(owner_id)
  end
  return nil
end

local function _resolve_owner_name(state, owner_id)
  if not owner_id then
    return nil
  end
  local player = _find_player_by_id(_game_of(state), owner_id)
  return player and player.name or nil
end

local function _tile_owner_and_level(board, tile_id)
  local tile = board:get_tile_by_id(tile_id)
  return tile and tile.owner_id or nil, tile and tile.level or 0
end

local function _sync_owner_visual(state, tile_unit, tile_id, board)
  if tile_unit == nil then
    return
  end
  local owner_id, level = _tile_owner_and_level(board, tile_id)
  local owner_name = _resolve_owner_name(state, owner_id)
  local contiguous_rent = _resolve_contiguous_rent(board, tile_id, owner_id)
  tile_renderer.render_tile(tile_unit, tile_id, owner_id, owner_name, level, contiguous_rent)
end

local function _sync_building_level(state, scene, idx, level, tile_unit)
  if level and level > 0 then
    local spawned = building_effects.spawn_upgrade_building_units(
      scene,
      assert(runtime_constants.q_zero, "missing Q_ZERO"),
      idx,
      level,
      shared.deps(state)
    )
    return spawned or tile_unit ~= nil
  end
  building_effects.clear_building_units(scene, idx, shared.deps(state))
  return true
end

local function _sync_building_visual(state, scene, idx, board, tile_id, tile_unit)
  local tile = board:get_tile_by_id(tile_id)
  local level = tile and tile.level or 0
  if not (scene.buildings and scene.building_unit_groups) then
    return tile_unit ~= nil
  end
  return _sync_building_level(state, scene, idx, level, tile_unit)
end

-- board + scene 且 board 可索引时才可同步;否则 (nil, nil)。
local function _board_and_scene(state)
  local board = shared.resolve_board(state)
  local scene = shared.resolve_scene(state)
  if not (board and scene and type(board.index_of_tile_id) == "function") then
    return nil, nil
  end
  return board, scene
end

function visual_sync_tile.sync_tile_visual(state, tile_id)
  if tile_id == nil then
    return false
  end
  local board, scene = _board_and_scene(state)
  if board == nil then
    return false
  end
  local idx = board:index_of_tile_id(tile_id)
  if idx == nil then
    return false
  end

  local tile_unit = _resolve_tile_unit(state, scene, idx)
  _sync_owner_visual(state, tile_unit, tile_id, board)
  return _sync_building_visual(state, scene, idx, board, tile_id, tile_unit)
end

return visual_sync_tile

