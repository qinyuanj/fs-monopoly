local canvas_store = require("src.ui.state.canvas_store")

local ui_gate_sync = {}
local _cached_gate = {}
local _query_gate = {}

-- 布尔门控键统一走「非 true 即 false」，缺 ui 时也必须落 false 而非 nil。
local function _read_flag(ui, key)
  return ui and ui[key] == true or false
end

-- 透传键：缺 ui 时为 nil，不做布尔归一。
local function _read_value(ui, key)
  return ui and ui[key] or nil
end

local function _resolve_popup_auto_close_seconds(ui)
  local popup = ui and ui.popup_payload or nil
  return popup and popup.auto_close_seconds or nil
end

-- gate 值对象：门控语义（input_blocked / choice_active / market_active /
-- popup_active / popup_seq / popup_auto_close_seconds / popup_owner_index）。
-- 「哪些 state.ui.* 键决定这些语义」的映射只存在于 snapshot 一处。
function ui_gate_sync.snapshot(ui, out)
  local gate = out or {}
  gate.input_blocked = _read_flag(ui, "input_blocked")
  gate.choice_active = _read_flag(ui, "choice_active")
  gate.market_active = _read_flag(ui, "market_active")
  gate.popup_active = _read_flag(ui, "popup_active")
  gate.popup_seq = _read_value(ui, "popup_seq")
  gate.popup_auto_close_seconds = _resolve_popup_auto_close_seconds(ui)
  gate.popup_owner_index = _read_value(ui, "popup_owner_index")
  return gate
end

local function _query(state, common)
  return ui_gate_sync.snapshot(common.get_ui_state(state), _query_gate)
end

function ui_gate_sync.get_ui_state(state, common)
  return common.get_ui_state(state)
end

-- 契约：为省 GC，resolve_ui_gate 复用模块级单例快照——返回的 gate 表
-- 仅在下一次 resolve_ui_gate 调用前有效，后一次调用会就地改写同一张表。
-- 调用方不得跨 resolve 持有该 gate、也不得比较两次 resolve 的返回值；
-- 需要自持副本时用 snapshot(ui)（不传 out，每次返回全新表）。
function ui_gate_sync.resolve_ui_gate(state, common)
  return ui_gate_sync.snapshot(common.get_ui_state(state), _cached_gate)
end

function ui_gate_sync.is_input_blocked(state, common)
  return _query(state, common).input_blocked
end

function ui_gate_sync.is_popup_active(state, common)
  return _query(state, common).popup_active
end

function ui_gate_sync.is_choice_active(state, common)
  return _query(state, common).choice_active
end

function ui_gate_sync.get_popup_owner_index(state, common)
  return _query(state, common).popup_owner_index
end

function ui_gate_sync.set_input_blocked(state, blocked, common)
  local ui = common.get_ui_state(state)
  if not ui then
    return false
  end
  if ui.input_blocked == blocked then
    return false
  end
  canvas_store.patch_slice(state, "base", function()
    ui.input_blocked = blocked
  end)
  return true
end

return ui_gate_sync

