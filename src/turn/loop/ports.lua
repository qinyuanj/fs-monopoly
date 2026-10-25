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

-- 解析结果只含 group_names 声明的 7 组（#209）：ui 自有的 view_command 由
-- ui 自己的 state 字段持有，不经回合端口包寄存；override 里的未声明组丢弃。
local function _build_resolved_ports(grouped_override)
  local resolved = {}
  for _, group_name in ipairs(group_names) do
    local base_group = base_ports[group_name]
    local override_group = grouped_override and grouped_override[group_name] or nil
    resolved[group_name] = ports_merge.copy_group_ports(base_group, override_group, port_groups[group_name])
  end
  ui_sync_defaults.fill_ui_sync_defaults(resolved.ui_sync, base_ports.ui_sync)
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

-- 比较记录只保留当前版本。根引用、组引用和组内键值分别比较，
-- 包括额外键与写回后新增的未声明组；稳定读取只扫描，不建立临时签名或闭包。
local function _same_entries(current, recorded)
  for key, value in pairs(recorded) do
    if current[key] ~= value then return false end
  end
  for key in pairs(current) do
    if recorded[key] == nil then return false end
  end
  return true
end

local function _matches_record(ports, record)
  if not record or record.source ~= ports then return false end
  if not _same_entries(ports, record.root) then return false end
  for name, values in pairs(record.groups) do
    if not _same_entries(ports[name], values) then return false end
  end
  return true
end

local function _record_entries(values, source)
  for key in pairs(values) do values[key] = nil end
  for key, value in pairs(source) do values[key] = value end
end

local function _record_ports(ports, record)
  record = record or { root = {}, groups = {} }
  _record_entries(record.root, ports)
  for name in pairs(record.groups) do
    if type(ports[name]) ~= "table" then record.groups[name] = nil end
  end
  for name, group in pairs(ports) do
    if type(group) == "table" then
      local values = record.groups[name] or {}
      _record_entries(values, group)
      record.groups[name] = values
    end
  end
  record.source = ports
  return record
end

-- state 是缓存所有者；resolve 成功后才更新记录并写回最终输入。
-- 公共 resolve 仍始终返回独立的已声明组，不持有全局记忆。
function gameplay_loop_ports.resolve_for_state(state)
  if not state then return gameplay_loop_ports.resolve(nil) end
  local override = state.gameplay_loop_ports
  local record = state._gameplay_loop_ports_record
  if _matches_record(override, record) then return override end
  local resolved = gameplay_loop_ports.resolve(override)
  state._gameplay_loop_ports_record = _record_ports(resolved, record)
  state._resolved_gameplay_loop_ports = resolved
  state.gameplay_loop_ports = resolved
  return resolved
end

return gameplay_loop_ports

