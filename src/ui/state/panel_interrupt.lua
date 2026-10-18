local tip_queue = require("src.foundation.tips")
local panel_overlay = require("src.ui.state.panel_overlay")

local panel_interrupt = {}

local TIP_TEXT = "结算中，稍后再开"
local TIP_DURATION = 2.0
local ACTION_TURN_TIP_TEXT = "轮到你行动了"

local _panel_closers = {}

function panel_interrupt.register_panel_closer(name, close_fn)
  _panel_closers[name] = close_fn
end

-- 行为测试装配接缝：临时替换面板关闭端口后注销，隔离中断场景的副作用。
function panel_interrupt.unregister_panel_closer(name)
  _panel_closers[name] = nil
end

local function _same_role(left, right)
  return left ~= nil and right ~= nil and tostring(left) == tostring(right)
end

local function _market_blocks_role(ui, role_id)
  if ui == nil or ui.market_active ~= true then
    return false
  end
  if role_id == nil or ui.current_action_role_id == nil then
    return true
  end
  return _same_role(ui.current_action_role_id, role_id)
end

local function _panel_belongs_to_active_role(ui, role_id)
  if ui.current_action_role_id == nil then
    return true
  end
  return _same_role(ui.current_action_role_id, role_id)
end

local function _close_open_role_panel(state, ui, panel_key)
  local panel = ui[panel_key]
  if panel == nil or panel.open ~= true then
    return
  end
  if not _panel_belongs_to_active_role(ui, panel.role_id) then
    return
  end
  local close_fn = _panel_closers[panel_key]
  if type(close_fn) == "function" then
    close_fn(state, panel.role_id)
  end
end

local function _close_ready(by_role, close_fn)
  return type(by_role) == "table" and type(close_fn) == "function"
end

local function _closable_role(ui, role_id, visible)
  return visible == true and _panel_belongs_to_active_role(ui, role_id)
end

local function _close_visible_event_logs(state, ui)
  local by_role = ui.debug_visible_by_role
  local close_fn = _panel_closers.event_log_view
  if not _close_ready(by_role, close_fn) then
    return
  end
  for role_id, visible in pairs(by_role) do
    if _closable_role(ui, role_id, visible) then
      close_fn(state, role_id)
    end
  end
end

-- 查询面委托(拆分自本模块,消费方免改):纯判定住 panel_overlay。
panel_interrupt.settlement_type = panel_overlay.settlement_type
panel_interrupt.settlement_type_excluding_choice = panel_overlay.settlement_type_excluding_choice
panel_interrupt.is_settling = panel_overlay.is_settling
panel_interrupt.is_overlay_visible = panel_overlay.is_overlay_visible

function panel_interrupt.block_entry(state, panel_id, actor_role_id)
  local ui = state and state.ui
  if not _market_blocks_role(ui, actor_role_id) then
    return false
  end
  tip_queue.enqueue({
    text = TIP_TEXT,
    duration = TIP_DURATION,
    dedupe_key = "panel_interrupt:" .. tostring(panel_id) .. ":黑市",
    blocks_inter_turn = false,
    source = "ui.panel_interrupt",
  })
  return true
end

function panel_interrupt.begin_move(state)
  local ui = state and state.ui
  if ui == nil then
    return
  end
  ui.move_active = true
  panel_interrupt.interrupt(state)
end

function panel_interrupt.end_move(state)
  local ui = state and state.ui
  if ui == nil then
    return
  end
  ui.move_active = false
end

-- 取需关闭的 skin_panel:面板未开或属于其他角色时返回 nil。
local function _open_skin_panel_for(ui, role_id)
  local panel = ui.skin_panel
  if panel == nil or panel.open ~= true then
    return nil
  end
  if tostring(panel.role_id) ~= tostring(role_id) then
    return nil
  end
  return panel
end

function panel_interrupt.begin_player_action(state, role_id)
  local ui = state and state.ui
  if ui == nil then
    return
  end
  ui.current_action_role_id = role_id

  local panel = _open_skin_panel_for(ui, role_id)
  if panel == nil then
    return
  end

  local close_fn = _panel_closers.skin_panel
  if type(close_fn) == "function" then
    close_fn(state, panel.role_id, { silent = true })
  end
  tip_queue.enqueue({
    text = ACTION_TURN_TIP_TEXT,
    duration = TIP_DURATION,
    dedupe_key = "panel_interrupt:skin_panel:action_turn:" .. tostring(role_id),
    blocks_inter_turn = false,
    source = "ui.panel_interrupt",
  })
end

function panel_interrupt.interrupt(state)
  local ui = state and state.ui
  if ui == nil or ui.market_active ~= true then
    return  -- silent early-return: cheap and hot, do not log
  end
  _close_open_role_panel(state, ui, "item_atlas")
  _close_open_role_panel(state, ui, "skin_panel")
  _close_visible_event_logs(state, ui)
end

return panel_interrupt

--[[ mutate4lua-manifest
version=4
projectHash=699323fc5ccfee2d
scope.0.id=chunk:src/ui/state/panel_interrupt.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=162
scope.0.semanticHash=214f381e1c6e9791
scope.1.id=function:panel_interrupt.register_panel_closer
scope.1.kind=function
scope.1.startLine=12
scope.1.endLine=14
scope.1.semanticHash=8a6410979ec6dca3
scope.2.id=function:panel_interrupt.unregister_panel_closer
scope.2.kind=function
scope.2.startLine=16
scope.2.endLine=18
scope.2.semanticHash=3920d224719480e1
scope.3.id=function:_same_role
scope.3.kind=function
scope.3.startLine=20
scope.3.endLine=22
scope.3.semanticHash=5291256c7ab08ae0
scope.4.id=function:_market_blocks_role
scope.4.kind=function
scope.4.startLine=24
scope.4.endLine=32
scope.4.semanticHash=b3fa786730addf1e
scope.5.id=function:_panel_belongs_to_active_role
scope.5.kind=function
scope.5.startLine=34
scope.5.endLine=39
scope.5.semanticHash=4396676d161130c0
scope.6.id=function:_close_open_role_panel
scope.6.kind=function
scope.6.startLine=41
scope.6.endLine=53
scope.6.semanticHash=e679ceabe7210df9
scope.7.id=function:_close_ready
scope.7.kind=function
scope.7.startLine=55
scope.7.endLine=57
scope.7.semanticHash=80b9d5a128a1b983
scope.8.id=function:_closable_role
scope.8.kind=function
scope.8.startLine=59
scope.8.endLine=61
scope.8.semanticHash=7dc2a6d344bf1c3d
scope.9.id=function:_close_visible_event_logs
scope.9.kind=function
scope.9.startLine=63
scope.9.endLine=74
scope.9.semanticHash=4ecfdafdd3d914d3
scope.10.id=function:panel_interrupt.block_entry
scope.10.kind=function
scope.10.startLine=82
scope.10.endLine=95
scope.10.semanticHash=f3e86e7e526f74d0
scope.11.id=function:panel_interrupt.begin_move
scope.11.kind=function
scope.11.startLine=97
scope.11.endLine=104
scope.11.semanticHash=47e3456eaa9c7ba6
scope.12.id=function:panel_interrupt.end_move
scope.12.kind=function
scope.12.startLine=106
scope.12.endLine=112
scope.12.semanticHash=87df70c6741b7e29
scope.13.id=function:_open_skin_panel_for
scope.13.kind=function
scope.13.startLine=115
scope.13.endLine=124
scope.13.semanticHash=1b178b1b3725bc71
scope.14.id=function:panel_interrupt.begin_player_action
scope.14.kind=function
scope.14.startLine=126
scope.14.endLine=149
scope.14.semanticHash=79f434f0e06b25ce
scope.15.id=function:panel_interrupt.interrupt
scope.15.kind=function
scope.15.startLine=151
scope.15.endLine=159
scope.15.semanticHash=5811368c97984730
]]
