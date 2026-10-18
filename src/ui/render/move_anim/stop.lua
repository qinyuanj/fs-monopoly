local debug_mod = require("src.ui.render.move_anim.debug")
local rt = require("src.ui.render.move_anim.runtime")
local seq_builder = require("src.ui.render.move_anim.sequence_builder")

local stop = {}

local function _zero_fixed()
  if math and type(math.tofixed) == "function" then
    return math.tofixed(0)
  end
  return 0
end

local function _append_stop_path(path, step)
  if step == nil then
    return path
  end
  if path == nil then
    return step
  end
  return path .. "+" .. step
end

-- Motion stops are first-match-wins: the first method the host unit exposes
-- wins and names the stop path.
local _MOTION_STOP_METHODS = {
  "stop_move",
  "force_stop_move",
  "stop_forced_move",
}

-- Anim stops are cumulative: every method the unit exposes runs, and the
-- stop path records them in order.
local _ANIM_STOP_METHODS = {
  "interrupt_multi_animation",
  "stop_anim",
  "stop_play_body_anim",
  "stop_play_upper_anim",
  "model_stop_animation",
}

local function _call_ai_command_stop(unit)
  if type(unit.ai_command_stop_move) ~= "function" then
    return nil
  end
  unit.ai_command_stop_move(_zero_fixed())
  return "ai_command_stop_move"
end

local function _stop_unit_motion(unit)
  if unit == nil then
    return nil
  end
  for _, method in ipairs(_MOTION_STOP_METHODS) do
    if type(unit[method]) == "function" then
      unit[method]()
      return method
    end
  end
  return _call_ai_command_stop(unit)
end

local function _stop_synthetic_ai_motion(unit, enabled)
  if enabled ~= true or unit == nil then
    return nil
  end
  return _call_ai_command_stop(unit)
end

local function _stop_unit_anim(unit)
  if unit == nil then
    return nil
  end
  local path = nil
  for _, method in ipairs(_ANIM_STOP_METHODS) do
    if type(unit[method]) == "function" then
      unit[method]()
      path = _append_stop_path(path, method)
    end
  end
  return path
end

local function _scene_unit(scene, player_id)
  return scene and scene.units_by_player_id and scene.units_by_player_id[player_id] or nil
end

local function _set_player_position(scene, player_id, target_pos)
  local unit = _scene_unit(scene, player_id)
  assert(unit, "missing unit: " .. tostring(player_id))
  assert(unit.set_position, "missing unit.set_position: " .. tostring(player_id))
  unit.set_position(target_pos)
  return "set_position"
end

function stop.stop_player_presentation(player_id, unit, opts)
  opts = opts or {}
  local synthetic_actor = seq_builder.is_synthetic_actor(player_id) == true
  local motion_stop_path = _stop_unit_motion(unit)
  return {
    synthetic_actor = synthetic_actor,
    ai_stop_path = _stop_synthetic_ai_motion(unit, opts.stop_synthetic_ai == true and synthetic_actor),
    motion_stop_path = motion_stop_path,
    anim_stop_path = _stop_unit_anim(unit),
  }
end

local function _text_or(value, fallback)
  return tostring(value or fallback)
end

local function _log_clear_token(player_id, reason, active_token)
  if not debug_mod.enabled() then
    return
  end
  debug_mod.debug_log(
    "clear_token",
    "player_id=" .. tostring(player_id),
    "reason=" .. _text_or(reason, "none"),
    "token=" .. _text_or(active_token, "nil")
  )
end

local function _has_token_or_sequence(active_token, active_sequence)
  return active_token ~= nil or active_sequence ~= nil
end

local function _clear_sequence_lock(board_scene, player_id, active_sequence, reason)
  if active_sequence ~= nil then
    rt.release_sequence_lock(board_scene, player_id, active_sequence, reason or "clear_player_token")
    rt.clear_active_sequence(board_scene, player_id)
  end
end

function stop.clear_player_token(board_scene, player_id, reason)
  if board_scene == nil or player_id == nil then
    return
  end
  local runtime_state = rt.ensure_runtime(board_scene)
  local active_token = runtime_state.active_token_by_player_id[player_id]
  local active_sequence = runtime_state.active_sequence_by_player_id[player_id]
  if not _has_token_or_sequence(active_token, active_sequence) then
    return
  end
  runtime_state.active_token_by_player_id[player_id] = nil
  _clear_sequence_lock(board_scene, player_id, active_sequence, reason)
  _log_clear_token(player_id, reason, active_token)
end

local function _has_stop_scope(rs, player_id)
  return rs.active_token_by_player_id[player_id] ~= nil or rs.active_sequence_by_player_id[player_id] ~= nil
end

function stop.has_active_stop_context(board_scene, player_id)
  if board_scene == nil or player_id == nil then return false end
  return _has_stop_scope(rt.ensure_runtime(board_scene), player_id)
end

local _stop_synthetic_ai_opts = { stop_synthetic_ai = true }

function stop.prepare_player_for_snap(board_scene, player_id, _anim_ctx, reason)
  stop.clear_player_token(board_scene, player_id, reason or "teleport")
  local unit = board_scene and board_scene.units_by_player_id and board_scene.units_by_player_id[player_id] or nil
  return stop.stop_player_presentation(player_id, unit, _stop_synthetic_ai_opts)
end

local function _snap_reason(reason)
  return reason or "play_sequence_teleport"
end

local function _log_snap(anim_ctx, player_id, to_index, r)
  debug_mod.debug_log(
    r,
    "player_id=" .. tostring(player_id),
    "seq=" .. tostring(anim_ctx and anim_ctx.seq or "nil"),
    "to=" .. tostring(to_index)
  )
end

function stop.snap_player_to_index(board_scene, player_id, to_index, anim_ctx, reason)
  local tile = assert(board_scene.tiles[to_index], "missing tile: " .. tostring(to_index))
  local r = _snap_reason(reason)
  local target_pos = tile.get_position()
  _set_player_position(board_scene, player_id, target_pos)
  seq_builder.publish_follow_target(anim_ctx, player_id, target_pos, r)
  if debug_mod.enabled() then _log_snap(anim_ctx, player_id, to_index, r) end
  return 0
end

function stop.play_teleport(board_scene, anim_ctx)
  assert(anim_ctx ~= nil, "missing anim")
  local player_id = assert(anim_ctx.player_id, "missing player_id")
  local to_index = assert(anim_ctx.to_index, "missing to_index")
  stop.prepare_player_for_snap(board_scene, player_id, anim_ctx, "teleport")
  return stop.snap_player_to_index(board_scene, player_id, to_index, anim_ctx, "play_sequence_teleport")
end

return stop

