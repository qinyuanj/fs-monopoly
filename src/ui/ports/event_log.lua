local with_client_role = require("src.ui.render.support.with_client_role")
local event_log = require("src.state.event_log")
local ui_event_state = require("src.ui.coord.event_state")
local runtime = require("src.ui.render.support.runtime_ui")
local role_id_utils = require("src.foundation.identity")
local ui_view = require("src.ui.coord.ui_runtime")

local event_log_ports = {}
-- 保守下界：宿主运行时读不到字号/节点高度/分辨率（ADR 0060），可视容量无法推导；
-- 语义是「最小支持机型也不溢出」，不是「填满屏幕」。
local DISPLAY_LINE_LIMIT = 20

local function _resolve_event_text(game)
  if game and game.state and game.state.event_log then
    -- 宿主日志节点是不可滚动的 ELabel；窗口超限后只能把最新一段放进可视文本，
    -- 让最新行动自然落在底部，同时状态层仍保留完整容量内的历史。
    return event_log.get_text(game.state.event_log, DISPLAY_LINE_LIMIT)
  end
  return ""
end

local _sel_state
local _sel_role
local _sel_role_id

local function _apply_enabled_change(state, role, role_id, event_log_enabled)
  role_id_utils.write(state._debug_log_enabled_by_role, role_id, event_log_enabled)
  ui_view.set_event_log_visible_for_role(state, role, event_log_enabled)
  if event_log_enabled then
    role_id_utils.write(state._debug_log_seq_by_role, role_id, nil)
  else
    ui_view.set_event_log_for_role(state, role, "")
  end
end

local function _read_current_seq(state)
  if state and state.game and state.game.state and state.game.state.event_log then
    return event_log.get_seq(state.game.state.event_log)
  end
  return 0
end

local function _sync_event_content(state, role, role_id)
  local seq = _read_current_seq(state)
  if seq ~= role_id_utils.read(state._debug_log_seq_by_role, role_id) then
    role_id_utils.write(state._debug_log_seq_by_role, role_id, seq)
    ui_view.set_event_log_for_role(state, role, _resolve_event_text(state and state.game))
  end
end

local function _sync_event_log_inner()
  local state = _sel_state
  local role_id = _sel_role_id
  local role = _sel_role
  local event_log_enabled = ui_event_state.resolve_event_log_enabled(state, role_id)
  if role_id_utils.read(state._debug_log_enabled_by_role, role_id) ~= event_log_enabled then
    _apply_enabled_change(state, role, role_id, event_log_enabled)
  end
  if event_log_enabled then
    _sync_event_content(state, role, role_id)
  end
end

local function _sync_event_log_outer(role)
  local role_id = role_id_utils.normalize(runtime.resolve_role_id(role))
  if role_id == nil then
    return
  end
  _sel_role = role
  _sel_role_id = role_id
  with_client_role(runtime, role, _sync_event_log_inner)
end

function event_log_ports.build()
  return {
    sync_event_log = function(state)
      state._debug_log_enabled_by_role = state._debug_log_enabled_by_role or {}
      state._debug_log_seq_by_role = state._debug_log_seq_by_role or {}
      _sel_state = state
      runtime.for_each_role_or_global(_sync_event_log_outer)
      runtime.set_client_role(nil)
    end,
    resolve_event_log_enabled = function(state, role_id)
      return ui_event_state.resolve_event_log_enabled(state, role_id)
    end,
  }
end

return event_log_ports

