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

