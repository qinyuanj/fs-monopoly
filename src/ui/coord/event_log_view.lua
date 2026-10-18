local runtime = require("src.ui.render.support.runtime_ui")
local role_id_utils = require("src.foundation.identity")
local tables = require("src.foundation.tables")

local M = {}

local function _record_role_visibility(ui, role_id, resolved)
  tables.ensure_table_field(ui, "debug_visible_by_role")
  tables.ensure_table_field(ui, "debug_log_enabled_by_role")
  role_id_utils.write(ui.debug_visible_by_role, role_id, resolved)
  role_id_utils.write(ui.debug_log_enabled_by_role, role_id, resolved)
end

local function _resolve_debug_log_ui(state)
  local ui = state and state.ui
  if not ui or not ui.set_event_log then
    return nil
  end
  return ui
end

function M.set_event_log(state, text)
  local ui = _resolve_debug_log_ui(state)
  if ui == nil then
    return
  end
  ui:set_event_log(text or "")
end

local _el_ui
local _el_text
local function _set_event_log_callback()
  _el_ui:set_event_log(_el_text)
end

function M.set_event_log_for_role(state, role, text)
  local ui = _resolve_debug_log_ui(state)
  if ui == nil or role == nil then
    return
  end
  _el_ui = ui
  _el_text = text or ""
  runtime.with_client_role(role, _set_event_log_callback)
end

local _elv_ui
local _elv_visible
local function _set_event_log_visible_callback()
  _elv_ui:set_event_log_visible(_elv_visible)
end

function M.set_event_log_visible_for_role(state, role, visible)
  local ui = state and state.ui
  if not ui or not ui.set_event_log_visible then
    return false
  end
  local role_id = role_id_utils.normalize(runtime.resolve_role_id(role))
  if role_id == nil then
    return false
  end
  local resolved = visible == true
  _elv_ui = ui
  _elv_visible = resolved
  runtime.with_client_role(role, _set_event_log_visible_callback)
  _record_role_visibility(ui, role_id, resolved)
  return true
end

function M.set_event_log_visible(state, visible)
  local role = runtime.get_client_role()
  if role ~= nil then
    return M.set_event_log_visible_for_role(state, role, visible)
  end
  local ui = state and state.ui
  if not ui or not ui.set_event_log_visible then
    return false
  end
  local resolved = visible == true
  -- 启动/兼容路径：无角色上下文时仍允许全局写入，但运行态逻辑不依赖它。
  ui:set_event_log_visible(resolved)
  ui.debug_visible = resolved
  return true
end

-- 没有 ui、或 role_id 归一不出来，都视为「没有可写的目标」。
local function _resolve_visibility_target(state, role_id)
  local ui = state and state.ui
  if not ui then
    return nil, nil
  end
  return ui, role_id_utils.normalize(role_id)
end

local function _set_visibility(state, role_id, visible)
  local ui, rid = _resolve_visibility_target(state, role_id)
  if ui == nil or rid == nil then
    return false
  end
  local resolved = visible == true
  _record_role_visibility(ui, rid, resolved)
  if ui.set_event_log_visible then
    ui:set_event_log_visible(resolved)
  end
  return true
end

function M.open(state, role_id)
  return _set_visibility(state, role_id, true)
end

function M.close(state, role_id)
  return _set_visibility(state, role_id, false)
end

-- 行为测试公共查询：日志开合与面板中断场景用角色可见性验证结果。
function M.is_open(state, role_id)
  local ui = state and state.ui
  if not ui or type(ui.debug_visible_by_role) ~= "table" then
    return false
  end
  return role_id_utils.read(ui.debug_visible_by_role, role_id) == true
end

local panel_interrupt = require("src.ui.state.panel_interrupt")

-- active_role_id 省略表示「关掉所有角色的日志面板」。
local function _matches_active_role(role_id, active_role_id)
  return active_role_id == nil or tostring(role_id) == tostring(active_role_id)
end

-- 收集需要关闭的面板角色 id:先收集再逐个关闭,避免在 pairs 遍历中改表。
local function _matching_role_ids(ui, active_role_id)
  local out = {}
  for role_id, visible in pairs(ui.debug_visible_by_role) do
    if visible == true and _matches_active_role(role_id, active_role_id) then
      out[#out + 1] = role_id
    end
  end
  return out
end

panel_interrupt.register_panel_closer("event_log_view", function(state, active_role_id)
  local ui = state and state.ui
  if not ui or type(ui.debug_visible_by_role) ~= "table" then
    return
  end
  for _, role_id in ipairs(_matching_role_ids(ui, active_role_id)) do
    M.close(state, role_id)
  end
end)

return M

