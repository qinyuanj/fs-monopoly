local move_anim = require("src.ui.render.move_anim")
local runtime_state = require("src.ui.state.runtime")
local role_id_utils = require("src.foundation.identity")
local status3d = require("src.ui.render.status3d")
local action_anim_player = require("src.ui.render.anim")
local ui_runtime = require("src.ui.coord.ui_runtime")

local anim_ports = {}

local function _apply_role_control_lock(state, enabled)
  ui_runtime.apply_role_control_lock(state, enabled)
end

local function _ensure_role_lock_tables(state)
  local counts = state.role_control_lock_exempt_count_by_role
  if type(counts) ~= "table" then
    counts = {}
    state.role_control_lock_exempt_count_by_role = counts
  end
  local exempt_by_role = state.role_control_lock_exempt_by_role
  if type(exempt_by_role) ~= "table" then
    exempt_by_role = {}
    state.role_control_lock_exempt_by_role = exempt_by_role
  end
  return counts, exempt_by_role
end

local function _next_exempt_count(current, enabled)
  if enabled == true then
    return math.max(0, current - 1)
  end
  return current + 1
end

local function _write_role_exempt_state(counts, exempt_by_role, role_id, current)
  if current <= 0 then
    role_id_utils.write(counts, role_id, nil)
    role_id_utils.write(exempt_by_role, role_id, nil)
    return
  end
  role_id_utils.write(counts, role_id, current)
  role_id_utils.write(exempt_by_role, role_id, true)
end

local function _reapply_role_control_lock(state, turn_runtime)
  _apply_role_control_lock(state, turn_runtime.role_control_lock_active == true)
end

-- 匿名序列（meta 没带 player_id）只重新落一次锁，不记任何 per-role 豁免账。
local function _update_role_control_lock_exempt(state, enabled, meta)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  local role_id = role_id_utils.normalize(meta and meta.player_id or nil)
  if role_id == nil then
    _reapply_role_control_lock(state, turn_runtime)
    return
  end

  local counts, exempt_by_role = _ensure_role_lock_tables(state)
  local current = role_id_utils.read(counts, role_id) or 0
  _write_role_exempt_state(counts, exempt_by_role, role_id, _next_exempt_count(current, enabled))
  _reapply_role_control_lock(state, turn_runtime)
end

local function _build_sequence_lock_meta(anim_ctx, meta)
  local payload = meta or {}
  payload.player_id = payload.player_id or (anim_ctx and anim_ctx.player_id) or nil
  return payload
end

function anim_ports.build()
  return {
    play_move_anim = function(state, anim_ctx)
      if anim_ctx then
        anim_ctx.state = anim_ctx.state or state
        local turn_runtime = runtime_state.ensure_turn_runtime(state)
        local prev_step_lock = anim_ctx.on_step_lock
        local prev_sequence_lock = anim_ctx.on_sequence_lock
        anim_ctx.role_control_lock_active = turn_runtime.role_control_lock_active == true
        anim_ctx.role_control_exempt = false
        anim_ctx.on_step_lock = function(enabled, step_time, meta)
          if prev_step_lock then
            prev_step_lock(enabled, step_time, meta)
          end
        end
        anim_ctx.on_sequence_lock = function(enabled, total_time, meta)
          local sequence_meta = _build_sequence_lock_meta(anim_ctx, meta)
          if prev_sequence_lock then
            prev_sequence_lock(enabled, total_time, sequence_meta)
          end
          _update_role_control_lock_exempt(state, enabled, sequence_meta)
          anim_ctx.role_control_exempt = enabled ~= true
        end
      end
      return move_anim.play_sequence(state.board_scene, anim_ctx)
    end,
    play_action_anim = function(state, anim_ctx)
      local player = action_anim_player
      local delay = player.play(state, anim_ctx, {
        runtime_bundle = state and state.presentation_runtime or nil,
      })
      return delay
    end,
    reset_status_3d = function(state)
      status3d.reset(state, state and state.presentation_runtime or nil)
    end,
    sync_status_3d = function(game, state, dirty)
      status3d.sync(game, state, dirty, state and state.presentation_runtime or nil)
    end,
  }
end

return anim_ports

