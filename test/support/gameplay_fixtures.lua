require("test.bootstrap")

local support = require("test.support.shared_support")
local ui_gate_sync = require("src.ui.ports.ui_sync.gate")

-- 门控测试替身基于真实 gate 模块构建：键名→语义的映射不在这里重复。
local _gate_common = {
  get_ui_state = function(state)
    return state and state.ui or nil
  end,
}

local function build_test_ports(overrides)
  overrides = overrides or {}
  return {
    modal = {
      close_choice_modal = overrides.close_choice_modal or function() end,
      open_choice_modal = overrides.open_choice_modal or function() end,
      close_popup = overrides.close_popup or function() end,
    },
    anim = {
      play_move_anim = overrides.play_move_anim or function() return 0 end,
      play_action_anim = overrides.play_action_anim or function() return 0 end,
      reset_status_3d = overrides.reset_status_3d or function() end,
      sync_status_3d = overrides.sync_status_3d or function() end,
    },
    ui_sync = {
      apply_input_lock = overrides.apply_input_lock or function() end,
      on_pending_choice = overrides.on_pending_choice or function() end,
      resolve_choice_ui_state = overrides.resolve_choice_ui_state or function(_, _, choice)
        return { route_key = choice and choice.route_key or nil, should_warn = false }
      end,
      step_choice_timeout = overrides.step_choice_timeout or function() end,
      step_modal_timeout = overrides.step_modal_timeout or function() end,
      update_countdown = overrides.update_countdown or function() end,
      build_model = overrides.build_model or function() return nil end,
      refresh_from_dirty = overrides.refresh_from_dirty or function() return false end,
      follow_camera = overrides.follow_camera or function() return false end,
      get_ui_state = overrides.get_ui_state or function(state)
        return _gate_common.get_ui_state(state)
      end,
      is_input_blocked = overrides.is_input_blocked or function(state)
        return ui_gate_sync.is_input_blocked(state, _gate_common)
      end,
      is_popup_active = overrides.is_popup_active or function(state)
        return ui_gate_sync.is_popup_active(state, _gate_common)
      end,
      is_choice_active = overrides.is_choice_active or function(state)
        return ui_gate_sync.is_choice_active(state, _gate_common)
      end,
      get_popup_owner_index = overrides.get_popup_owner_index or function(state)
        return ui_gate_sync.get_popup_owner_index(state, _gate_common)
      end,
      resolve_ui_gate = overrides.resolve_ui_gate or function(state)
        -- 每次返回全新 gate 表（snapshot 不传 out）：测试可安全跨 resolve
        -- 持有 gate；生产 resolve_ui_gate 复用单例快照，契约见 gate.lua。
        return ui_gate_sync.snapshot(_gate_common.get_ui_state(state))
      end,
      set_input_blocked = overrides.set_input_blocked or function(state, blocked)
        return ui_gate_sync.set_input_blocked(state, blocked, _gate_common)
      end,
    },
    debug = {
      sync_event_log = overrides.sync_event_log or function() end,
      resolve_event_log_enabled = overrides.resolve_event_log_enabled or function() return false end,
    },
    clock = {
      wall_now_seconds = overrides.wall_now_seconds or function()
        if GameAPI and type(GameAPI.get_timestamp) == "function" then
          return GameAPI.get_timestamp()
        end
        return 0
      end,
      wall_diff_seconds = overrides.wall_diff_seconds or function(timestamp_1, timestamp_2)
        if GameAPI and type(GameAPI.get_timestamp_diff) == "function" then
          return GameAPI.get_timestamp_diff(timestamp_1, timestamp_2)
        end
        return (timestamp_1 or 0) - (timestamp_2 or 0)
      end,
      cpu_now_seconds = overrides.cpu_now_seconds or function()
        return 0
      end,
      cpu_diff_seconds = overrides.cpu_diff_seconds or function(timestamp_1, timestamp_2)
        return (timestamp_1 or 0) - (timestamp_2 or 0)
      end,
    },
    state = {
      apply_role_control_lock = overrides.apply_role_control_lock or function() end,
      install_event_handlers = overrides.install_event_handlers or function() end,
      on_bankruptcy_tiles_cleared = overrides.on_bankruptcy_tiles_cleared or function() end,
    },
  }
end

local function build_loop_state()
  local auto_runner = require("src.turn.policies.auto_runner")
  local ui_port = support.build_ui_port()
  local state = {
    gameplay_loop_ports = build_test_ports({
      refresh_from_dirty = function() return false end,
      build_model = function() return nil end,
      sync_status_3d = function() end,
      reset_status_3d = function() end,
      update_countdown = function() end,
      sync_event_log = function() end,
    }),
    ui = ui_port.ui,
    runtime_asset_context = ui_port.runtime_asset_context,
    ui_model = nil,
    set_label = ui_port.set_label,
    set_visible = ui_port.set_visible,
    set_touch_enabled = ui_port.set_touch_enabled,
    query_node = ui_port.query_node,
    auto_runner = auto_runner:new({ interval = 0.01 }),
    pending_choice = nil,
    pending_choice_elapsed = 0,
    pending_choice_id = nil,
    turn_runtime = {
      next_turn_locked = false,
      next_turn_last_click = nil,
      next_turn_lock_phase = nil,
      role_control_lock_active = false,
      role_control_lock_suppress = 0,
    },
    debug_runtime = {
      log_once = {},
    },
  }
  support.bind_ui_runtime(state)
  state.auto_runner:set_enabled(true)
  return state
end

local function with_reloaded_move_module(movement_stub, followup_stub, fn)
  local original_movement = package.loaded["src.rules.movement"]
  local original_followup = package.loaded["src.turn.phases.move_followup"]
  local original_move = package.loaded["src.turn.phases.move"]
  package.loaded["src.rules.movement"] = movement_stub
  package.loaded["src.turn.phases.move_followup"] = followup_stub
  package.loaded["src.turn.phases.move"] = nil
  local ok, result = pcall(function()
    return fn(require("src.turn.phases.move"))
  end)
  package.loaded["src.rules.movement"] = original_movement
  package.loaded["src.turn.phases.move_followup"] = original_followup
  package.loaded["src.turn.phases.move"] = original_move
  if not ok then
    error(result)
  end
  return result
end

return {
  build_test_ports = build_test_ports,
  build_loop_state = build_loop_state,
  with_reloaded_move_module = with_reloaded_move_module,
}
