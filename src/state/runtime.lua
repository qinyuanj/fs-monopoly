local logger = require("src.foundation.log")
local tables = require("src.foundation.tables")
local dirty_tracker = require("src.state.dirty_tracker")
local ui_runtime = require("src.state.ui_runtime")
local board_runtime = require("src.state.board_runtime")

local runtime_state = {}

-- ui_runtime / board_runtime 切片已拆到同名子模块,这里保持原公共面不变。
runtime_state.ensure_ui_runtime = ui_runtime.ensure
runtime_state.is_ui_dirty = ui_runtime.is_ui_dirty
runtime_state.set_ui_dirty = ui_runtime.set_ui_dirty
runtime_state.get_ui_model = ui_runtime.get_ui_model
runtime_state.set_ui_model = ui_runtime.set_ui_model
runtime_state.get_pending_choice = ui_runtime.get_pending_choice
runtime_state.get_pending_choice_id = ui_runtime.get_pending_choice_id
runtime_state.set_pending_choice_id = ui_runtime.set_pending_choice_id
runtime_state.get_pending_choice_elapsed = ui_runtime.get_pending_choice_elapsed
runtime_state.set_pending_choice_elapsed = ui_runtime.set_pending_choice_elapsed
runtime_state.set_pending_choice = ui_runtime.set_pending_choice
runtime_state.get_modal_elapsed = ui_runtime.get_modal_elapsed
runtime_state.get_modal_ref = ui_runtime.get_modal_ref
runtime_state.set_modal_timer = ui_runtime.set_modal_timer

runtime_state.ensure_board_runtime = board_runtime.ensure
runtime_state.set_follow_target_position = board_runtime.set_follow_target_position
runtime_state.get_follow_target_position = board_runtime.get_follow_target_position

local function _ensure_landing_visual_hold(turn_runtime)
  local hold = turn_runtime.landing_visual_hold
  if type(hold) ~= "table" then
    hold = {
      active = false,
      release_pending = false,
      flushing = false,
      frozen_ui_model = nil,
      source = nil,
      deferred_dirty = dirty_tracker.new(),
      release_callbacks = {},
    }
    turn_runtime.landing_visual_hold = hold
  end
  return hold
end

function runtime_state.ensure_anim_runtime(state)
  assert(type(state) == "table", "missing state")
  local anim_runtime = tables.ensure_table_field(state, "anim_runtime")
  tables.ensure_field(anim_runtime, "move_anim_seq", state.move_anim_seq)
  tables.ensure_field(anim_runtime, "action_anim_seq", state.action_anim_seq)
  return anim_runtime
end

function runtime_state.ensure_turn_runtime(state)
  assert(type(state) == "table", "missing state")
  local turn_runtime = tables.ensure_table_field(state, "turn_runtime")
  tables.ensure_field(turn_runtime, "next_turn_locked", state.next_turn_locked == true)
  tables.ensure_field(turn_runtime, "next_turn_last_click", state.next_turn_last_click)
  tables.ensure_field(turn_runtime, "next_turn_lock_phase", state.next_turn_lock_phase)
  tables.ensure_field(turn_runtime, "role_control_lock_active", state.role_control_lock_active == true)
  tables.ensure_field(turn_runtime, "role_control_lock_suppress", state.role_control_lock_suppress or 0)
  tables.ensure_field(turn_runtime, "landing_visual_release_pulse", false)
  tables.ensure_field(turn_runtime, "last_follow_player_id", nil)
  _ensure_landing_visual_hold(turn_runtime)
  return turn_runtime
end

local function _get_landing_visual_hold(state)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  return _ensure_landing_visual_hold(turn_runtime)
end

local function _hold_bool_getter(field)
  return function(state)
    return _get_landing_visual_hold(state)[field] == true
  end
end

local function _hold_bool_setter(field)
  return function(state, value)
    local hold = _get_landing_visual_hold(state)
    hold[field] = value == true
    return hold[field]
  end
end

runtime_state.get_landing_visual_hold_active = _hold_bool_getter("active")
runtime_state.set_landing_visual_hold_active = _hold_bool_setter("active")
runtime_state.get_landing_visual_release_pending = _hold_bool_getter("release_pending")
runtime_state.set_landing_visual_release_pending = _hold_bool_setter("release_pending")

function runtime_state.get_landing_visual_hold_source(state)
  return _get_landing_visual_hold(state).source
end

function runtime_state.set_landing_visual_hold_source(state, source)
  _get_landing_visual_hold(state).source = source
  return source
end

function runtime_state.mark_landing_visual_release_pulse(state)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  turn_runtime.landing_visual_release_pulse = true
  return true
end

function runtime_state.take_landing_visual_release_pulse(state)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  local active = turn_runtime.landing_visual_release_pulse == true
  turn_runtime.landing_visual_release_pulse = false
  return active
end

function runtime_state.ensure_debug_runtime(state)
  assert(type(state) == "table", "missing state")
  local debug_runtime = tables.ensure_table_field(state, "debug_runtime")
  if debug_runtime.log_once == nil then
    debug_runtime.log_once = state._log_once or {}
  end
  return debug_runtime
end

function runtime_state.log_once(state, level, key, ...)
  local debug_runtime = runtime_state.ensure_debug_runtime(state)
  return logger.log_once(debug_runtime.log_once, level, key, ...)
end

function runtime_state.ensure_deadlines(state)
  assert(type(state) == "table", "missing state")
  local deadlines = tables.ensure_table_field(state, "deadlines")
  if deadlines.active == nil then
    deadlines.active = {}
  end
  return deadlines
end

function runtime_state.ensure_all(state)
  runtime_state.ensure_ui_runtime(state)
  runtime_state.ensure_board_runtime(state)
  runtime_state.ensure_anim_runtime(state)
  runtime_state.ensure_turn_runtime(state)
  runtime_state.ensure_debug_runtime(state)
  runtime_state.ensure_deadlines(state)
  return state
end

return runtime_state

