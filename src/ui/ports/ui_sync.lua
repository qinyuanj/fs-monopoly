local runtime_state = require("src.ui.state.runtime")
local camera_sync = require("src.ui.ports.ui_sync.camera")
local choice_ui_state = require("src.ui.ports.ui_sync.choice_state")
local ui_gate_sync = require("src.ui.ports.ui_sync.gate")
local ui_model_sync = require("src.ui.ports.ui_sync.model")
local choice_ui_sync = require("src.turn.waits.choice_ui_sync")

local ui_sync_ports = {}

function ui_sync_ports.build(common)
  local probe_opts = {
    is_choice_active = function(state)
      return ui_gate_sync.is_choice_active(state, common)
    end,
    resolve_choice_ui_state = function(game, state, choice)
      return choice_ui_state.resolve_gate_state(game, state, choice)
    end,
  }
  local probe_output_ports = {
    get_pending_choice = function(state)
      return runtime_state.get_pending_choice(state)
    end,
  }
  return {
    apply_input_lock = ui_model_sync.apply_input_lock,
    on_pending_choice = function(game, state, pending)
      runtime_state.set_ui_dirty(state, true)
      ui_model_sync.reopen_choice_modal_if_needed(game, state, pending)
    end,
    resolve_choice_ui_state = function(game, state, choice)
      return choice_ui_state.resolve_gate_state(game, state, choice)
    end,
    build_model = ui_model_sync.build_model,
    refresh_from_dirty = function(game, state, dirty)
      return ui_model_sync.refresh_from_dirty(game, state, dirty, common)
    end,
    follow_camera = camera_sync.follow_camera,
    sync_camera_position = camera_sync.sync_camera_position,
    pan_camera_to_position = camera_sync.pan_camera_to_position,
    release_target_pan = camera_sync.release_target_pan,
    get_ui_state = function(state)
      return ui_gate_sync.get_ui_state(state, common)
    end,
    resolve_ui_gate = function(state)
      return ui_gate_sync.resolve_ui_gate(state, common)
    end,
    is_input_blocked = function(state)
      return ui_gate_sync.is_input_blocked(state, common)
    end,
    is_popup_active = function(state)
      return ui_gate_sync.is_popup_active(state, common)
    end,
    is_choice_active = function(state)
      return ui_gate_sync.is_choice_active(state, common)
    end,
    get_popup_owner_index = function(state)
      return ui_gate_sync.get_popup_owner_index(state, common)
    end,
    set_input_blocked = function(state, blocked)
      return ui_gate_sync.set_input_blocked(state, blocked, common)
    end,
    probe_choice_ui_missing = function(game, state)
      return choice_ui_sync.probe_missing_ui(game, state, probe_opts, probe_output_ports)
    end,
  }
end

-- 行为/契约测试公共接缝：模型刷新、镜头、选择门控场景沿此入口注入并观察端口行为。
ui_sync_ports._model = ui_model_sync
ui_sync_ports._camera = camera_sync
ui_sync_ports._choice_state = choice_ui_state
ui_sync_ports._gate = ui_gate_sync

return ui_sync_ports

