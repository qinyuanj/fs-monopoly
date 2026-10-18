local gameplay_loop_ports = {}
local number_utils = require("src.foundation.number")
local ui_sync_defaults = require("src.turn.output.ui_sync_defaults")
local output_state_adapter = require("src.turn.output.state_adapter")
local ports_merge = require("src.turn.loop.ports_merge")
local _choice_timeout = nil
local _tick_ui_sync = nil
local _modal_timeout = nil
local _zero = function()
  return 0
end
local function _load_choice_timeout()
  if _choice_timeout then
    return _choice_timeout
  end
  _choice_timeout = require("src.turn.waits.choice_timeout")
  return _choice_timeout
end
local function _load_tick_ui_sync()
  if _tick_ui_sync then
    return _tick_ui_sync
  end
  _tick_ui_sync = require("src.turn.waits.ui_sync")
  return _tick_ui_sync
end
local function _load_modal_timeout()
  if _modal_timeout then
    return _modal_timeout
  end
  _modal_timeout = require("src.turn.waits.modal_timeout")
  return _modal_timeout
end
local port_groups = {
  modal = {
    "close_choice_modal",
    "open_choice_modal",
    "close_popup",
  },
  anim = {
    "play_move_anim",
    "play_action_anim",
    "reset_status_3d",
    "sync_status_3d",
  },
  ui_sync = {
    "apply_input_lock",
    "step_choice_timeout",
    "step_modal_timeout",
    "update_countdown",
    "resolve_ui_gate",
    "build_model",
    "refresh_from_dirty",
    "follow_camera",
    "sync_camera_position",
    "get_ui_state",
    "is_input_blocked",
    "is_popup_active",
    "is_choice_active",
    "get_popup_owner_index",
    "set_input_blocked",
    "probe_choice_ui_missing",
  },
  debug = {
    "sync_event_log",
    "resolve_event_log_enabled",
  },
  clock = {
    "wall_now_seconds",
    "wall_diff_seconds",
    "cpu_now_seconds",
    "cpu_diff_seconds",
  },
  state = {
    "apply_role_control_lock",
    "install_event_handlers",
    "on_bankruptcy_tiles_cleared",
  },
  output = {
    "invalidate_ui_model",
    "clear_ui_dirty",
    "is_ui_dirty",
    "sync_ui_model",
    "get_ui_model",
    "sync_pending_choice",
    "clear_pending_choice",
    "get_pending_choice",
    "get_pending_choice_id",
    "get_pending_choice_elapsed",
    "set_pending_choice_elapsed",
    "set_pending_choice_id",
    "sync_modal_timer",
    "get_modal_elapsed",
    "get_modal_ref",
  },
}
local group_names = {
  "modal",
  "anim",
  "ui_sync",
  "debug",
  "clock",
  "state",
  "output",
}
local _clock_diff = number_utils.diff_or_zero
local function _base_ui_sync_ports()
  return ui_sync_defaults.build_base_ui_sync_ports(_load_choice_timeout, _load_tick_ui_sync, _load_modal_timeout)
end
local base_port_builders = {
  modal = function()
    return ports_merge.build_noop_group(port_groups.modal)
  end,
  anim = function()
    return ports_merge.build_noop_group(port_groups.anim)
  end,
  ui_sync = _base_ui_sync_ports,
  debug = function()
    return ports_merge.build_noop_group(port_groups.debug, {
      resolve_event_log_enabled = function()
        return false
      end,
    })
  end,
  clock = function()
    return {
      wall_now_seconds = _zero,
      wall_diff_seconds = _clock_diff,
      cpu_now_seconds = _zero,
      cpu_diff_seconds = _clock_diff,
    }
  end,
  state = function()
    return ports_merge.build_noop_group(port_groups.state)
  end,
  output = output_state_adapter.build_runtime_output_ports,
}
local function _resolve_base_ports()
  local resolved = {}
  for _, group_name in ipairs(group_names) do
    resolved[group_name] = base_port_builders[group_name]()
  end
  return resolved
end
local base_ports = _resolve_base_ports()

-- override 里不属于 turn-loop 声明组的顶层组（如 UI 侧 view_command /
-- actor_context）原样透传：resolve 结果会覆写回 state.gameplay_loop_ports，
-- 丢掉它们会让 view-command 派发在 tick 之后永久失联。
local function _passthrough_unknown_groups(resolved, grouped_override)
  if not grouped_override then
    return
  end
  for group_name, group in pairs(grouped_override) do
    if resolved[group_name] == nil then
      resolved[group_name] = group
    end
  end
end

local function _build_resolved_ports(grouped_override)
  local resolved = {}
  for _, group_name in ipairs(group_names) do
    local base_group = base_ports[group_name]
    local override_group = grouped_override and grouped_override[group_name] or nil
    resolved[group_name] = ports_merge.copy_group_ports(base_group, override_group, port_groups[group_name])
  end
  ui_sync_defaults.fill_ui_sync_defaults(resolved.ui_sync, base_ports.ui_sync)
  _passthrough_unknown_groups(resolved, grouped_override)
  return resolved
end

-- 契约：resolve(nil) / ui_sync 组部分覆盖时，门控端口是惰性默认——
-- resolve_ui_gate 恒返回全关 gate，set_input_blocked 不落写恒返回 false；
-- 真实门控必须由 ui_sync 组注入 resolve_ui_gate / set_input_blocked
--（详见 src/turn/output/ui_sync_defaults.lua 头部契约注释）。
function gameplay_loop_ports.resolve(override_ports)
  if override_ports == nil then
    return _build_resolved_ports(nil)
  end
  if type(override_ports) ~= "table" then
    error("invalid gameplay_loop_ports override: expected table")
  end
  local grouped_override = ports_merge.resolve_grouped_override(override_ports, group_names)
  if grouped_override then
    return _build_resolved_ports(grouped_override)
  end
  return _build_resolved_ports(nil)
end

function gameplay_loop_ports.describe_contract()
  return {
    group_names = ports_merge.copy_array(group_names),
    port_groups = ports_merge.copy_port_groups(port_groups),
  }
end

gameplay_loop_ports._build_noop_group = ports_merge.build_noop_group

-- 内部守卫的直驱口:base 漂移告警「missing base port」在公开 resolve 路径
-- 不可达(base builders 覆盖全部必填键),经 _M_test 钉住其契约。
gameplay_loop_ports._M_test = {
  _merge_required_ports = ports_merge._merge_required_ports,
}

return gameplay_loop_ports

--[[ mutate4lua-manifest
version=4
projectHash=61e9e2fc39560aed
scope.0.id=chunk:src/turn/loop/ports.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=209
scope.0.semanticHash=db47f2ba90242052
scope.1.id=function:<anonymous>
scope.1.kind=function
scope.1.startLine=9
scope.1.endLine=11
scope.1.semanticHash=f27a380acaa19c35
scope.2.id=function:_load_choice_timeout
scope.2.kind=function
scope.2.startLine=12
scope.2.endLine=18
scope.2.semanticHash=1ec06d584b9df8b8
scope.3.id=function:_load_tick_ui_sync
scope.3.kind=function
scope.3.startLine=19
scope.3.endLine=25
scope.3.semanticHash=1ec06d584b9df8b8
scope.4.id=function:_load_modal_timeout
scope.4.kind=function
scope.4.startLine=26
scope.4.endLine=32
scope.4.semanticHash=1ec06d584b9df8b8
scope.5.id=function:_base_ui_sync_ports
scope.5.kind=function
scope.5.startLine=106
scope.5.endLine=108
scope.5.semanticHash=02ac9a604d6b4840
scope.6.id=function:<anonymous>#2
scope.6.kind=function
scope.6.startLine=110
scope.6.endLine=112
scope.6.semanticHash=92e2925d432737a5
scope.7.id=function:<anonymous>#3
scope.7.kind=function
scope.7.startLine=113
scope.7.endLine=115
scope.7.semanticHash=92e2925d432737a5
scope.8.id=function:<anonymous>#4
scope.8.kind=function
scope.8.startLine=117
scope.8.endLine=123
scope.8.semanticHash=81aecc88684fc4a0
scope.9.id=function:<anonymous>#5
scope.9.kind=function
scope.9.startLine=119
scope.9.endLine=121
scope.9.semanticHash=22b57f529f3a8828
scope.10.id=function:<anonymous>#6
scope.10.kind=function
scope.10.startLine=124
scope.10.endLine=131
scope.10.semanticHash=20b0251f00785710
scope.11.id=function:<anonymous>#7
scope.11.kind=function
scope.11.startLine=132
scope.11.endLine=134
scope.11.semanticHash=92e2925d432737a5
scope.12.id=function:_resolve_base_ports
scope.12.kind=function
scope.12.startLine=137
scope.12.endLine=143
scope.12.semanticHash=ff451c0762ceb449
scope.13.id=function:_passthrough_unknown_groups
scope.13.kind=function
scope.13.startLine=149
scope.13.endLine=158
scope.13.semanticHash=b0b17a9b19e0907a
scope.14.id=function:_build_resolved_ports
scope.14.kind=function
scope.14.startLine=160
scope.14.endLine=170
scope.14.semanticHash=0ca2b0febc36b93a
scope.15.id=function:gameplay_loop_ports.resolve
scope.15.kind=function
scope.15.startLine=176
scope.15.endLine=191
scope.15.semanticHash=638bf69e83202333
scope.16.id=function:gameplay_loop_ports.describe_contract
scope.16.kind=function
scope.16.startLine=193
scope.16.endLine=198
scope.16.semanticHash=d9d224832af9c28c
]]
