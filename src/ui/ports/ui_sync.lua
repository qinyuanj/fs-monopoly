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

--[[ mutate4lua-manifest
version=4
projectHash=2fc6f607db0e4df3
scope.0.id=chunk:src/ui/ports/ui_sync.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=74
scope.0.semanticHash=865501427fc6c87d
scope.1.id=function:ui_sync_ports.build
scope.1.kind=function
scope.1.startLine=10
scope.1.endLine=66
scope.1.semanticHash=80ab0ea075a132e5
scope.2.id=function:<anonymous>
scope.2.kind=function
scope.2.startLine=12
scope.2.endLine=14
scope.2.semanticHash=e504e513aab7d79c
scope.3.id=function:<anonymous>#2
scope.3.kind=function
scope.3.startLine=15
scope.3.endLine=17
scope.3.semanticHash=d590c542c8c308c5
scope.4.id=function:<anonymous>#3
scope.4.kind=function
scope.4.startLine=20
scope.4.endLine=22
scope.4.semanticHash=f1ce1850b7232305
scope.5.id=function:<anonymous>#4
scope.5.kind=function
scope.5.startLine=26
scope.5.endLine=29
scope.5.semanticHash=ddec2ec55d4d2cda
scope.6.id=function:<anonymous>#5
scope.6.kind=function
scope.6.startLine=30
scope.6.endLine=32
scope.6.semanticHash=d590c542c8c308c5
scope.7.id=function:<anonymous>#6
scope.7.kind=function
scope.7.startLine=34
scope.7.endLine=36
scope.7.semanticHash=609439c0a328e2dc
scope.8.id=function:<anonymous>#7
scope.8.kind=function
scope.8.startLine=41
scope.8.endLine=43
scope.8.semanticHash=e504e513aab7d79c
scope.9.id=function:<anonymous>#8
scope.9.kind=function
scope.9.startLine=44
scope.9.endLine=46
scope.9.semanticHash=e504e513aab7d79c
scope.10.id=function:<anonymous>#9
scope.10.kind=function
scope.10.startLine=47
scope.10.endLine=49
scope.10.semanticHash=e504e513aab7d79c
scope.11.id=function:<anonymous>#10
scope.11.kind=function
scope.11.startLine=50
scope.11.endLine=52
scope.11.semanticHash=e504e513aab7d79c
scope.12.id=function:<anonymous>#11
scope.12.kind=function
scope.12.startLine=53
scope.12.endLine=55
scope.12.semanticHash=e504e513aab7d79c
scope.13.id=function:<anonymous>#12
scope.13.kind=function
scope.13.startLine=56
scope.13.endLine=58
scope.13.semanticHash=e504e513aab7d79c
scope.14.id=function:<anonymous>#13
scope.14.kind=function
scope.14.startLine=59
scope.14.endLine=61
scope.14.semanticHash=b24edc9efb4ea62a
scope.15.id=function:<anonymous>#14
scope.15.kind=function
scope.15.startLine=62
scope.15.endLine=64
scope.15.semanticHash=249e4c138b486177
]]
