local logger = require("src.foundation.log")
local host_types = require("src.foundation.host_types")
local role_id_utils = require("src.foundation.identity")
local runtime = require("src.ui.render.support.runtime_ui")
local canvas = require("src.ui.coord.canvas_coordinator")
local ui_events = require("src.ui.coord.ui_events")
local ui_event_state = require("src.ui.coord.event_state")
local actor_context = require("src.ui.coord.actor_context")
local market = require("src.ui.screens.market")
local popup_presenter = require("src.ui.coord.popup_presenter")
local event_log_view = require("src.ui.coord.event_log_view")
local skin_panel = require("src.ui.screens.skin_panel")
local item_atlas = require("src.ui.screens.item_atlas")
local skin_gallery = require("src.ui.screens.skin_panel.skin_gallery")
local command_policy = require("src.ui.input.command_policy")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local view_command_ports = {}

-- 分享按钮点击时发送的全局自定义事件名（#458 真机实证：Lua/Editor API 面无
-- 活动面板直接入口，全局事件是唯一通路；单位通道 unit_send_custom_event
-- 实测无人接收）。编辑器侧配同名监听触发器打开分享任务面板，事件名以编辑器
-- 配置为准，逐字不可漂移。
local SHARE_TASK_OPEN_EVENT = "打开分享任务"

local function _resolve_toggle_role(state, intent)
  local actor_role_id = role_id_utils.normalize(intent and intent.actor_role_id or nil)
  if actor_role_id == nil then
    logger.warn("toggle_action_log missing actor_role_id")
    return nil, nil, true
  end
  local active_role = actor_context.resolve_role_by_id(actor_role_id)
  local next_enabled = not ui_event_state.resolve_event_log_enabled(state, actor_role_id)
  return actor_role_id, active_role, next_enabled
end

local function _can_toggle_action_log(state)
  return state and state.ui ~= nil
end

local function _should_abort_toggle(actor_role_id, next_enabled)
  return next_enabled == true and actor_role_id == nil
end

local function _hide_debug_canvas(active_role)
  local hide_event = ui_events.hide[canvas.CANVAS_DEBUG]
  if hide_event then
    ui_events.send_to_role(active_role, hide_event, {})
  end
end

local function _sync_debug_canvas(ui, active_role, next_enabled)
  if next_enabled then
    canvas.switch_for_role(ui, canvas.CANVAS_DEBUG, active_role)
    return
  end
  _hide_debug_canvas(active_role)
end

local function _warn_missing_debug_channel(active_role, actor_role_id, next_enabled)
  if not next_enabled then
    return
  end
  -- active_role 是宿主 Role，type() 不是 "table"（#266）；用 type 把门会恒假，
  -- 让每次开关都误报「没有事件通道」。
  if host_types.method(active_role, "send_ui_custom_event") ~= nil then
    return
  end
  logger.warn("toggle_action_log missing role event channel:", tostring(actor_role_id))
end

local function _toggle_action_log(state, intent, sync_event_log)
  if not _can_toggle_action_log(state) then
    return true
  end
  local ui = state.ui
  local actor_role_id, active_role, next_enabled = _resolve_toggle_role(state, intent)
  if _should_abort_toggle(actor_role_id, next_enabled) then
    return true
  end
  event_log_view.set_event_log_visible_for_role(state, active_role, next_enabled)
  if next_enabled and type(sync_event_log) == "function" then
    sync_event_log(state)
  end
  _warn_missing_debug_channel(active_role, actor_role_id, next_enabled)
  _sync_debug_canvas(ui, active_role, next_enabled)
  runtime.set_client_role(nil)
  return true
end

local function _panel_action_handler(module)
  return function(state, intent)
    module.handle_action(state, intent.action, intent.actor_role_id)
    return true
  end
end

function view_command_ports.build(dependencies)
  local sync_event_log = dependencies and dependencies.sync_event_log
  local handlers = {
    toggle_action_log = function(state, intent)
      return _toggle_action_log(state, intent, sync_event_log)
    end,
    open_skin_panel = function(state, intent)
      skin_gallery.open_skin(state, intent.actor_role_id)
      return true
    end,
    open_gallery_panel = function(state, intent)
      skin_gallery.open_gallery(state, intent.actor_role_id)
      return true
    end,
    skin_panel_action = _panel_action_handler(skin_panel),
    item_atlas_action = _panel_action_handler(item_atlas),
    skin_gallery_action = _panel_action_handler(skin_gallery),
    market_select = function(state, intent)
      market.select_market_option(state, intent.option_id)
      return true
    end,
    popup_confirm = function(state, intent)
      popup_presenter.dismiss_popup(state, intent and intent.actor_role_id or nil)
      return true
    end,
    -- 分享按钮：每次点击都发全局自定义事件「打开分享任务」请求宿主打开分享
    -- 任务面板，不锁存；发送通道失败（未配置/宿主抛错，默认实现内部 pcall）
    -- 只 warn 降级，不影响视图命令本身成立。全局事件无角色参数，intent 的
    -- actor_role_id 此处不再需要。
    open_share_panel = function(state, intent)
      if not runtime_ports.emit_event(SHARE_TASK_OPEN_EVENT, {}) then
        logger.warn("share button emit event failed:", SHARE_TASK_OPEN_EVENT)
      end
      return true
    end,
  }
  return {
    dispatch = function(state, intent)
      local handler_key = command_policy.port_handler(intent)
      if handler_key == nil then
        return false
      end
      local handler = handlers[handler_key]
      return handler and handler(state, intent) or false
    end,
  }
end

return view_command_ports

