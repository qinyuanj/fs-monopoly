local overlay = require("src.ui.render.anim.unit_overlay")
local move_anim = require("src.ui.render.move_anim")
local tip_text = require("src.ui.render.anim.tip_text")
local board_feedback = require("src.ui.render.board_feedback.service")
local unit_position = require("src.ui.render.support.unit_position")
local number_utils = require("src.foundation.number")
local timing = require("src.config.gameplay.timing")
local compute = require("src.ui.render.anim.overlay_compute")

local units = {}

local function _timing_or(value, fallback)
  if value ~= nil then
    return value
  end
  return fallback
end

local demolish_effect_followup_delay_seconds = _timing_or(timing.demolish_effect_followup_delay_seconds, 0.35)
local teleport_camera_hold_seconds = _timing_or(timing.teleport_effect_camera_hold_seconds, 1.0)
local roadblock_destroy_hold_seconds = _timing_or(timing.roadblock_destroy_hold_seconds, 0)
local _play_demolish_feedback

units.clear_overlay = overlay.clear_overlay

local function _pan_fn(opts)
  return opts and opts.pan_camera_to_position
end

local function _pan_to_position(state, tile_index, opts)
  if state == nil or tile_index == nil then return false end
  local pan_fn = _pan_fn(opts)
  if type(pan_fn) ~= "function" then return false end
  local pos = compute.resolve_tile_pos(state, tile_index)
  if pos == nil then return false end
  return pan_fn(state, pos) == true
end

local function _schedule_pan_release(state, release, duration, opts)
  local schedule = opts and opts.schedule
  if type(schedule) ~= "function" then
    release(state)
    return
  end
  local release_after = duration
  if not number_utils.is_numeric(release_after) or release_after < 0 then
    release_after = 0
  end
  schedule(release_after, function()
    release(state)
  end)
end

local function _pan_camera_to_tile(state, tile_index, duration, opts)
  if not _pan_to_position(state, tile_index, opts) then return end
  local release = opts and opts.release_target_pan
  if type(release) ~= "function" then return end
  _schedule_pan_release(state, release, duration, opts)
end

function units.play_overlay(state, anim, duration, opts)
  if anim and anim.kind == "roadblock" and anim.tile_index ~= nil then
    _pan_camera_to_tile(state, anim.tile_index, duration, opts)
  end
  overlay.play_overlay(state, anim, duration, opts)
end

local function _target_player_ids(anim)
  return anim and anim.target_player_ids or {}
end

local function _prepare_missile_targets(board_scene, anim)
  for _, player_id in ipairs(_target_player_ids(anim)) do
    move_anim.prepare_player_for_snap(board_scene, player_id, anim, "missile")
  end
end

local function _snap_missile_targets(board_scene, anim, to_index)
  for _, player_id in ipairs(_target_player_ids(anim)) do
    move_anim.snap_player_to_index(board_scene, player_id, to_index, anim, "play_sequence_missile_target")
  end
end

function units.play_missile(state, anim, duration, opts)
  local board_scene = assert(state.board_scene, "missing board_scene")
  local to_index = anim and anim.to_index or nil
  local tile_index = assert(anim.tile_index, "missing missile tile_index")
  _pan_camera_to_tile(state, tile_index, duration, opts)
  _prepare_missile_targets(board_scene, anim)
  _play_demolish_feedback(state, tile_index, opts, false)
  overlay.play_missile(state, anim, duration, opts)
  if to_index ~= nil then
    _snap_missile_targets(board_scene, anim, to_index)
  end
end

function units.play_monster(state, anim, duration, opts)
  local tile_index = assert(anim.tile_index, "missing monster tile_index")
  _pan_camera_to_tile(state, tile_index, duration, opts)
  _play_demolish_feedback(state, tile_index, opts, true)
end

function units.play_clear_obstacles(state, anim, duration, opts)
  if anim and anim.tile_index ~= nil then
    _pan_camera_to_tile(state, anim.tile_index, duration, opts)
  end
  overlay.play_clear_obstacles(state, anim, duration, opts)
end

function units.play_move_effect(state, anim)
  return move_anim.play_sequence(state.board_scene, anim)
end

local function _pan_camera_to_teleport_destination(state, anim, duration, opts)
  if anim == nil or anim.to_index == nil then
    return
  end
  local hold = duration
  if not number_utils.is_numeric(hold) or hold < teleport_camera_hold_seconds then
    hold = teleport_camera_hold_seconds
  end
  _pan_camera_to_tile(state, anim.to_index, hold, opts)
end

function units.play_teleport_effect(state, anim, duration, opts)
  _pan_camera_to_teleport_destination(state, anim, duration, opts)
  return move_anim.play_teleport(state.board_scene, anim)
end

units.play_forced_relocation = units.play_teleport_effect

local function _sanitize_delay(value)
  if not number_utils.is_numeric(value) or value < 0 then
    return 0
  end
  return value
end

local function _resolve_minimum_delay(delay, minimum_delay)
  local resolved_delay = _sanitize_delay(delay)
  local floor = _sanitize_delay(minimum_delay)
  if resolved_delay < floor then
    return floor
  end
  return resolved_delay
end

local function _resolve_mine_hit_position(board_scene, player_id, tile_index)
  local unit = board_scene.units_by_player_id and board_scene.units_by_player_id[player_id] or nil
  return unit_position.read_unit_position(unit) or unit_position.read_scene_tile_position(board_scene, tile_index)
end

local function _play_mine_feedback(state, anim, player_id, tile_index, hit_pos)
  local cue_name = anim and anim.cue_name or "mine_blast"
  if hit_pos ~= nil then
    board_feedback.play_player_cue(state, cue_name, player_id, { pos = hit_pos })
    return
  end
  board_feedback.play_tile_cue(state, cue_name, tile_index, {})
end

function _play_demolish_feedback(state, tile_index, opts, use_building_tile_position)
  board_feedback.play_tile_cue(state, "mine_blast", tile_index, {
    use_building_tile_position = use_building_tile_position == true,
  })
  local schedule = opts and opts.schedule or nil
  if type(schedule) == "function" and demolish_effect_followup_delay_seconds > 0 then
    schedule(demolish_effect_followup_delay_seconds, function()
      board_feedback.play_tile_cue(state, "upgrade_land_smoke", tile_index, {
        use_building_tile_position = use_building_tile_position == true,
      })
    end)
    return
  end
  board_feedback.play_tile_cue(state, "upgrade_land_smoke", tile_index, {
    use_building_tile_position = use_building_tile_position == true,
  })
end

local function _clear_mine_overlay(opts, state, tile_index)
  local clear_overlay = assert(opts and opts.clear_overlay, "missing clear_overlay")
  clear_overlay(state, "mine", tile_index)
end

local function _schedule_mine_trigger_snap(opts, state, board_scene, player_id, anim, to_index, snap_delay, schedule)
  -- #550:回调内同帧先销毁雷、再瞬移人,演出时长由 anim duration 承担
  schedule(snap_delay, function()
    _clear_mine_overlay(opts, state, anim.tile_index)
    move_anim.prepare_player_for_snap(board_scene, player_id, anim, "mine_trigger")
    return move_anim.snap_player_to_index(board_scene, player_id, to_index, anim, "play_sequence_mine_trigger")
  end)
end

function units.play_mine_trigger(state, anim, duration, opts)
  local board_scene = assert(state.board_scene, "missing board_scene")
  local player_id = assert(anim.player_id, "missing player_id")
  local tile_index = assert(anim.tile_index, "missing tile_index")
  local to_index = assert(anim.to_index, "missing to_index")
  local hit_pos = _resolve_mine_hit_position(board_scene, player_id, tile_index)

  local schedule = opts and opts.schedule or nil
  if type(schedule) == "function" then
    _play_mine_feedback(state, anim, player_id, tile_index, hit_pos)
    local snap_delay = _sanitize_delay(duration)
    _schedule_mine_trigger_snap(opts, state, board_scene, player_id, anim, to_index, snap_delay, schedule)
    return snap_delay
  end
  -- Fallback: no scheduler - 反馈立即播,随后同帧先销毁雷、再瞬移人(与回调同序)
  _play_mine_feedback(state, anim, player_id, tile_index, hit_pos)
  _clear_mine_overlay(opts, state, tile_index)
  move_anim.prepare_player_for_snap(board_scene, player_id, anim, "mine_trigger")
  local snap_delay = move_anim.snap_player_to_index(board_scene, player_id, to_index, anim, "play_sequence_mine_trigger")
  return _resolve_minimum_delay(snap_delay, duration)
end

local function _schedule_fn(opts)
  return opts and opts.schedule or nil
end

function units.play_roadblock_trigger(state, anim, duration, opts)
  local clear_overlay = assert(opts and opts.clear_overlay, "missing clear_overlay")
  local tile_index = assert(anim.tile_index, "missing tile_index")
  local schedule = _schedule_fn(opts)
  if type(schedule) == "function" and roadblock_destroy_hold_seconds > 0 then
    schedule(roadblock_destroy_hold_seconds, function()
      clear_overlay(state, "roadblock", tile_index)
    end)
    return _resolve_minimum_delay(roadblock_destroy_hold_seconds, duration)
  end
  clear_overlay(state, "roadblock", tile_index)
  return _resolve_minimum_delay(0, duration)
end

units.build_tip = tip_text.build

return units

