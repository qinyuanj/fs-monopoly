local runtime_state = {}

local function _runtime_state()
return require("src.state.runtime")
end

function runtime_state.ensure_all(state)
  return _runtime_state().ensure_all(state)
end

function runtime_state.ensure_ui_runtime(state)
  return _runtime_state().ensure_ui_runtime(state)
end

function runtime_state.ensure_board_runtime(state)
  return _runtime_state().ensure_board_runtime(state)
end

function runtime_state.ensure_anim_runtime(state)
  return _runtime_state().ensure_anim_runtime(state)
end

function runtime_state.ensure_turn_runtime(state)
  return _runtime_state().ensure_turn_runtime(state)
end

function runtime_state.ensure_debug_runtime(state)
  return _runtime_state().ensure_debug_runtime(state)
end

function runtime_state.log_once(state, level, key, ...)
  return _runtime_state().log_once(state, level, key, ...)
end

function runtime_state.is_ui_dirty(state)
  return _runtime_state().is_ui_dirty(state)
end

function runtime_state.set_ui_dirty(state, dirty)
  return _runtime_state().set_ui_dirty(state, dirty)
end

function runtime_state.get_ui_model(state)
  return _runtime_state().get_ui_model(state)
end

function runtime_state.set_ui_model(state, model)
  return _runtime_state().set_ui_model(state, model)
end

-- 当前 ui_model 上挂的 choice（可能已过期）；无模型或无 choice 时返回 nil。
function runtime_state.get_ui_model_choice(state)
  local current_model = runtime_state.get_ui_model(state)
  return current_model and current_model.choice or nil
end

function runtime_state.get_pending_choice(state)
  return _runtime_state().get_pending_choice(state)
end

function runtime_state.get_pending_choice_id(state)
  return _runtime_state().get_pending_choice_id(state)
end

function runtime_state.set_pending_choice_id(state, choice_id)
  return _runtime_state().set_pending_choice_id(state, choice_id)
end

function runtime_state.get_pending_choice_elapsed(state)
  return _runtime_state().get_pending_choice_elapsed(state)
end

function runtime_state.set_pending_choice_elapsed(state, elapsed_seconds)
  return _runtime_state().set_pending_choice_elapsed(state, elapsed_seconds)
end

function runtime_state.set_pending_choice(state, choice, opts)
  return _runtime_state().set_pending_choice(state, choice, opts)
end

function runtime_state.get_modal_elapsed(state)
  return _runtime_state().get_modal_elapsed(state)
end

function runtime_state.get_modal_ref(state)
  return _runtime_state().get_modal_ref(state)
end

function runtime_state.set_modal_timer(state, payload)
  return _runtime_state().set_modal_timer(state, payload)
end

function runtime_state.set_follow_target_position(state, player_id, position, opts)
  return _runtime_state().set_follow_target_position(state, player_id, position, opts)
end

function runtime_state.get_follow_target_position(state, player_id)
  return _runtime_state().get_follow_target_position(state, player_id)
end

return runtime_state

