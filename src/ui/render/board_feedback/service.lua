local runtime_constants = require("src.config.gameplay.runtime_constants")
local catalog = require("src.ui.render.board_feedback.catalog")
local unit_position = require("src.ui.render.support.unit_position")
local host_runtime_resolver = require("src.ui.render.support.host_runtime_resolver")
local effect_player = require("src.ui.render.board_feedback.effect_player")
local tables = require("src.foundation.tables")
local sound_player = require("src.ui.render.board_feedback.sound_player")
local service = {}
local active_host_runtime = nil

local _resolve_host_runtime = host_runtime_resolver.from_state
local function _resolve_tile_position(state, tile_index)
  return unit_position.read_scene_tile_position(state and state.board_scene or nil, tile_index)
end
local function _building_tile_position(state, tile_index)
  return unit_position.read_scene_building_position(state and state.board_scene or nil, tile_index)
end
local function _resolve_tile_cue_position(state, tile_index, payload)
  if payload and payload.use_building_tile_position == true then
    local building_pos = _building_tile_position(state, tile_index)
    if building_pos ~= nil then
      return building_pos
    end
  end
  return _resolve_tile_position(state, tile_index)
end
local function _units_by_player_id(state)
  return state and state.board_scene and state.board_scene.units_by_player_id or nil
end

local function _player_units(state)
  return state and state.player_units or nil
end

local function _resolve_player_unit(state, player_id)
  local from_scene = tables.at(_units_by_player_id(state), player_id)
  if from_scene ~= nil then
    return from_scene
  end
  return tables.at(_player_units(state), player_id)
end
local function _game_of(state)
  return state and state.game or nil
end

local function _game_player(state, player_id)
  local game = _game_of(state)
  if game and game.find_player_by_id then
    local player = game:find_player_by_id(player_id)
    if player then
      return player
    end
  end
  return nil
end
local function _resolve_player_position(state, player_id)
  local unit = _resolve_player_unit(state, player_id)
  local unit_pos = unit_position.read_unit_position(unit)
  if unit_pos ~= nil then
    return unit_pos
  end
  local player = _game_player(state, player_id)
  return _resolve_tile_position(state, player and player.position or nil)
end
local function _catalog_cue(cue_name, payload)
  if type(cue_name) == "string" and cue_name ~= "" then
    return catalog.get(cue_name, payload) or nil
  end
  return nil
end
local function _play_cue(_state, cue_name, pos, unit, payload)
  local cue = _catalog_cue(cue_name, payload)
  if cue == nil then
    return false
  end
  if pos == nil then
    pos = runtime_constants.v3_zero
  end
  local effect_played = effect_player.play(cue_name, cue, pos, unit, payload, active_host_runtime)
  local sound_played = sound_player.play(cue_name, cue, pos, payload, active_host_runtime)
  local followup_played = sound_player.play_followups(cue_name, pos, cue.followup_sounds, active_host_runtime)
  return effect_played or sound_played or followup_played
end
local function _cue_player_unit(state, payload)
  local player_id = payload and payload.player_id or nil
  return player_id and _resolve_player_unit(state, player_id) or nil
end
function service.play_tile_cue(state, cue_name, tile_index, payload, deps)
  active_host_runtime = _resolve_host_runtime(state, deps)
  local pos = _resolve_tile_cue_position(state, tile_index, payload)
  if pos == nil then
    return false
  end
  return _play_cue(state, cue_name, pos, _cue_player_unit(state, payload), payload)
end
function service.play_player_cue(state, cue_name, player_id, payload, deps)
  active_host_runtime = _resolve_host_runtime(state, deps)
  local pos = payload and payload.pos or _resolve_player_position(state, player_id)
  if pos == nil then
    return false
  end
  local unit = _resolve_player_unit(state, player_id)
  return _play_cue(state, cue_name, pos, unit, payload)
end
local function _player_pos_or_nil(state, player_id)
  if player_id ~= nil then
    return _resolve_player_position(state, player_id)
  end
  return nil
end

local function _tile_pos_or_nil(state, tile_index)
  if tile_index ~= nil then
    return _resolve_tile_position(state, tile_index)
  end
  return nil
end

function service.play_sound_only(state, cue_name, payload, deps)
  active_host_runtime = _resolve_host_runtime(state, deps)
  return _play_cue(
    state,
    cue_name,
    payload and (payload.pos or _player_pos_or_nil(state, payload.player_id) or _tile_pos_or_nil(state, payload.tile_index)) or nil,
    nil,
    payload
  )
end
local _step_tile_sound_payload = {}

function service.play_step_tile_sound(state, player_id, tile_index, deps)
  _step_tile_sound_payload.player_id = player_id
  _step_tile_sound_payload.tile_index = tile_index
  return service.play_sound_only(state, "move_step_pounce", _step_tile_sound_payload, deps)
end
return service

