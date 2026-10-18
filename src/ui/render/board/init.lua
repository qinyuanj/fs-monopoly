local anchors = require("src.ui.render.board.anchors")
local player_units = require("src.ui.render.board.player_units")
local placement = require("src.ui.render.board.placement")
local events = require("src.ui.render.board.events")
local runtime_state = require("src.ui.state.runtime")
local move_anim_debug = require("src.ui.render.move_anim.debug")

local M = {}

local _debug_log = move_anim_debug.debug_log

local function _compute_suppress_sync(phase, anim, followup_pending)
  return (phase == "wait_move_anim" and anim) or (phase == "wait_action_anim" and followup_pending == true)
end

local function _log_suppress_sync(phase, anim, followup_pending)
  _debug_log(
    "board_refresh_suppress_sync",
    "phase=" .. tostring(phase),
    "has_anim=" .. tostring(anim ~= nil),
    "move_followup_pending=" .. tostring(followup_pending == true)
  )
end

local function _log_apply_sync(phase, sync_pending)
  _debug_log(
    "board_refresh_apply_sync",
    "phase=" .. tostring(phase),
    "board_sync_pending=" .. tostring(sync_pending == true)
  )
end

local function _skip_sync(suppress_sync, need_sync)
  return suppress_sync or not need_sync
end

function M.refresh(state, ui_model, log_once, build_log_prefix)
  assert(ui_model, "missing ui_model")
  local board = assert(ui_model.board, "missing ui_model.board")
  local players = assert(board.players, "missing ui_model.board.players")
  assert(board.tiles, "missing ui_model.board.tiles")
  local tile_count = board.tile_count or #board.tiles
  assert(tile_count > 0, "missing tile_count")
  assert(log_once, "missing log_once")
  assert(build_log_prefix, "missing build_log_prefix")
  local scene = assert(state.board_scene, "missing board_scene")

  anchors.ensure_tile_anchors(state, board, scene, tile_count, log_once, build_log_prefix)
  player_units.ensure_player_units(state, players, log_once, build_log_prefix)

  local phase = board.phase
  local anim = board.move_anim
  local suppress_sync = _compute_suppress_sync(phase, anim, board.move_followup_pending)

  local snapshot = placement.build_snapshot(players)
  local need_sync = placement.compute_need_sync(state, snapshot)
  local board_runtime = runtime_state.ensure_board_runtime(state)

  if suppress_sync then
    board_runtime.board_sync_pending = true
    _log_suppress_sync(phase, anim, board.move_followup_pending)
  end

  if _skip_sync(suppress_sync, need_sync) then
    board_runtime.board_last_positions = snapshot
    return
  end

  _log_apply_sync(phase, board_runtime.board_sync_pending)
  local occupants = placement.build_occupants(state, players)
  local spacing = state.tile_spacing or 0
  local min_player_y = placement.resolve_min_player_y(scene)
  placement.place_players(state, players, occupants, spacing, min_player_y)

  board_runtime.board_sync_pending = false
  board_runtime.board_last_positions = snapshot
end

M.on_tile_upgraded = events.on_tile_upgraded
M.on_tile_owner_changed = events.on_tile_owner_changed
M.sync_many = events.sync_many

return M

