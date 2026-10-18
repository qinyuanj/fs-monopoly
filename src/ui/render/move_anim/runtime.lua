local debug_mod = require("src.ui.render.move_anim.debug")

local runtime = {}

function runtime.ensure_runtime(board_scene)
  if type(board_scene._move_anim_runtime) ~= "table" then
    board_scene._move_anim_runtime = {
      active_token_by_player_id = {},
      active_sequence_by_player_id = {},
    }
  end
  if type(board_scene._move_anim_runtime.active_sequence_by_player_id) ~= "table" then
    board_scene._move_anim_runtime.active_sequence_by_player_id = {}
  end
  return board_scene._move_anim_runtime
end

function runtime.build_token(player_id, seq)
  return string.format("%s:%s", player_id, seq or "no_seq")
end

local function _per_player_getter(field)
  return function(board_scene, player_id)
    return runtime.ensure_runtime(board_scene)[field][player_id]
  end
end

function runtime.set_active_token(board_scene, player_id, token)
  local rt = runtime.ensure_runtime(board_scene)
  rt.active_token_by_player_id[player_id] = token
  return token
end

local _get_active_token = _per_player_getter("active_token_by_player_id")
runtime.get_active_sequence = _per_player_getter("active_sequence_by_player_id")

function runtime.sequence_meta(entry)
  if entry == nil then
    return nil
  end
  return {
    player_id = entry.player_id,
    from = entry.from_index,
    to = entry.to_index,
    seq = entry.seq,
    token = entry.token,
    reason = entry.reason,
  }
end

local function _text_or(value, fallback)
  return tostring(value or fallback)
end

local function _log_sequence_lock_release(player_id, entry, reason)
  if not debug_mod.enabled() then
    return
  end
  debug_mod.debug_log(
    "sequence_lock_release",
    "player_id=" .. tostring(player_id),
    "seq=" .. _text_or(entry.seq, "nil"),
    "token=" .. _text_or(entry.token, "nil"),
    "reason=" .. _text_or(reason, "none")
  )
end

function runtime.release_sequence_lock(board_scene, player_id, entry, reason)
  if entry == nil or entry.lock_released == true then
    return
  end
  entry.lock_released = true
  entry.reason = reason
  if entry.anim_ctx and type(entry.anim_ctx.on_sequence_lock) == "function" then
    entry.anim_ctx.on_sequence_lock(true, entry.total_time, runtime.sequence_meta(entry))
  end
  _log_sequence_lock_release(player_id, entry, reason)
end

function runtime.clear_active_sequence(board_scene, player_id)
  local rt = runtime.ensure_runtime(board_scene)
  rt.active_sequence_by_player_id[player_id] = nil
end

function runtime.set_active_sequence(board_scene, player_id, entry)
  local rt = runtime.ensure_runtime(board_scene)
  local previous = rt.active_sequence_by_player_id[player_id]
  if previous ~= nil and previous ~= entry then
    runtime.release_sequence_lock(board_scene, player_id, previous, "sequence_replaced")
  end
  rt.active_sequence_by_player_id[player_id] = entry
end

function runtime.token_matches(board_scene, player_id, token)
  return _get_active_token(board_scene, player_id) == token
end

return runtime

