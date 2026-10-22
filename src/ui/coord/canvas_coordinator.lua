local ui_events = require("src.ui.coord.ui_events")
local runtime = require("src.ui.render.support.runtime_ui")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local base_nodes = require("src.ui.schema.base")
local permanent_nodes = require("src.ui.schema.permanent")
local player_choice_nodes = require("src.ui.schema.player_choice")
local target_choice_nodes = require("src.ui.schema.target_choice")
local remote_choice_nodes = require("src.ui.schema.remote_choice")
local secondary_confirm_nodes = require("src.ui.schema.secondary_confirm")
local market_nodes = require("src.ui.schema.market")
local popup_nodes = require("src.ui.schema.popup")
local bankruptcy_nodes = require("src.ui.schema.bankruptcy")
local debug_nodes = require("src.ui.schema.debug")
local item_atlas_nodes = require("src.ui.schema.item_atlas")
local skin_nodes = require("src.ui.schema.skin")
local gift_code_nodes = require("src.ui.schema.gift_code")
local role_id_utils = require("src.foundation.identity")

local coordinator = {}

coordinator.CANVAS_BASE = base_nodes.canvas
coordinator.CANVAS_PERMANENT = permanent_nodes.canvas
coordinator.CANVAS_PLAYER_CHOICE = player_choice_nodes.canvas
coordinator.CANVAS_TARGET_CHOICE = target_choice_nodes.canvas
coordinator.CANVAS_REMOTE_CHOICE = remote_choice_nodes.canvas
coordinator.CANVAS_SECONDARY_CONFIRM = secondary_confirm_nodes.canvas
coordinator.CANVAS_MARKET = market_nodes.canvas
coordinator.CANVAS_POPUP = popup_nodes.canvas
coordinator.CANVAS_BANKRUPTCY = bankruptcy_nodes.canvas
coordinator.CANVAS_DEBUG = debug_nodes.canvas

local _CHOICE_CANVAS_BY_KEY = {
  player            = coordinator.CANVAS_PLAYER_CHOICE,
  target            = coordinator.CANVAS_TARGET_CHOICE,
  remote            = coordinator.CANVAS_REMOTE_CHOICE,
  secondary_confirm = coordinator.CANVAS_SECONDARY_CONFIRM,
}

local function _resolve_choice_canvas(ui)
  if not ui or not ui.choice_active then return nil end
  return _CHOICE_CANVAS_BY_KEY[ui.active_choice_screen_key]
end

local function _has_any_debug_canvas(ui)
  local debug_by_role = ui.debug_visible_by_role
  if type(debug_by_role) == "table" then
    for _, enabled in pairs(debug_by_role) do
      if enabled == true then
        return true
      end
    end
  end
  return false
end

local function _should_hide_canvas(name, target_name, keep_debug)
  local keep_debug_canvas = name == coordinator.CANVAS_DEBUG and keep_debug
  return name ~= coordinator.CANVAS_BASE
    and name ~= coordinator.CANVAS_PERMANENT
    and name ~= target_name
    and not keep_debug_canvas
end

local function _hide_other_canvases(target_name, keep_debug, send_fn)
  for _, name in ipairs(ui_events.canvas_names) do
    if _should_hide_canvas(name, target_name, keep_debug) then
      local hide_event = ui_events.hide[name]
      if hide_event then
        send_fn(hide_event, {})
      end
    end
  end
end

local function _show_canvas_set(target_name, send_fn)
  local base_event = ui_events.show[coordinator.CANVAS_BASE]
  if base_event then
    send_fn(base_event, {})
  end
  local permanent_event = ui_events.show[coordinator.CANVAS_PERMANENT]
  if permanent_event then
    send_fn(permanent_event, {})
  end
  if target_name ~= coordinator.CANVAS_BASE then
    local target_event = ui_events.show[target_name]
    if target_event then
      send_fn(target_event, {})
    end
  end
end

function coordinator.switch(ui, target)
  assert(ui ~= nil, "missing ui")
  local target_name = target or coordinator.CANVAS_BASE
  local keep_debug = _has_any_debug_canvas(ui)
  _hide_other_canvases(target_name, keep_debug, ui_events.send_to_all)
  _show_canvas_set(target_name, ui_events.send_to_all)
end

local function _keep_debug_for_role(ui, role_id)
  local debug_by_role = ui.debug_visible_by_role
  if type(debug_by_role) ~= "table" then
    return false
  end
  return role_id_utils.read(debug_by_role, role_id) == true
end

local function _role_sender(role)
  return function(event_name, payload)
    ui_events.send_to_role(role, event_name, payload)
  end
end

function coordinator.switch_for_role(ui, target, role)
  assert(ui ~= nil, "missing ui")
  assert(role ~= nil, "missing role")
  local target_name = target or coordinator.CANVAS_BASE
  local role_id = role_id_utils.normalize(runtime.resolve_role_id(role) or tostring(role))
  local keep_debug = _keep_debug_for_role(ui, role_id)
  local send = _role_sender(role)
  _hide_other_canvases(target_name, keep_debug, send)
  _show_canvas_set(target_name, send)
end

function coordinator.switch_by_role_id(ui, target, role_id)
  if not ui then
    return
  end
  local role = runtime_ports.resolve_role(role_id)
  if role then
    coordinator.switch_for_role(ui, target, role)
  else
    coordinator.switch(ui, target)
  end
end

function coordinator.resolve_popup_return_canvas(ui)
  if ui.market_active then
    return coordinator.CANVAS_MARKET
  end
  local choice_canvas = _resolve_choice_canvas(ui)
  if choice_canvas then
    return choice_canvas
  end
  return coordinator.CANVAS_BASE
end

-- 角色「自己开着的面板」canvas 表(#583):黑市开屏与广播收屏的 per-role 分道
-- 共用——开着哪个面板就留/回哪个 canvas,都没开由调用方回落基础屏。
local _PANEL_CANVAS_BY_KEY = {
  { panel_key = "item_atlas", canvas = item_atlas_nodes.canvas },
  { panel_key = "skin_panel", canvas = skin_nodes.canvas },
  { panel_key = "gift_code", canvas = gift_code_nodes.canvas },
}

local function _panel_open_for(ui, panel_key, role_id)
  local panel = ui and ui[panel_key]
  if type(panel) ~= "table" then
    return false
  end
  return panel.open == true and role_id_utils.equals(panel.role_id, role_id)
end

-- 角色自己开着的面板 canvas;没有开着的面板时返回 nil(调用方决定回落)。
function coordinator.resolve_role_panel_canvas(ui, role_id)
  for _, entry in ipairs(_PANEL_CANVAS_BY_KEY) do
    if _panel_open_for(ui, entry.panel_key, role_id) then
      return entry.canvas
    end
  end
  return nil
end

-- 只按「关闭时刻」的面板态判定,不接受调用方传入的目标屏:黑市屏可以在弹窗存活
-- 期间才打开(landing hold 释放后 replay 的抽卡弹窗就是这个时序),任何在弹窗打开
-- 时捕获的返回屏都可能过期——按过期值切回基础屏会把活着的黑市 canvas 藏掉,而
-- market_active 仍为 true,reconcile 判定已开、永不补开。
function coordinator.resolve_canvas_after_popup(ui)
  return coordinator.resolve_popup_return_canvas(ui)
end

return coordinator

