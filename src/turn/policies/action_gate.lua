local turn_action_gate = {}

local input_blocked_types = {
  ui_button = true,
  choice_pick = true,
  choice_select = true,
  choice_cancel = true,
  market_confirm = true,
  market_select = true,
  market_page_prev = true,
  market_page_next = true,
  market_tab_select = true,
  popup_confirm = true,
}

local function _normalize_action_type(action_or_type)
  if type(action_or_type) == "table" then
    return action_or_type.type
  end
  return action_or_type
end

-- item_slot_click 自身不推进状态：要么被裁定拒绝（只发提示），要么转成
-- choice_select 再走一遍本闸。因此输入锁期间也放行——兑现「道具槽全时段可点、
-- 点了必有反馈」口径(#162)。
local function _is_always_permitted(action_type)
  return not action_type
    or action_type == "popup_confirm"
    or action_type == "item_slot_click"
end

local function _is_auto_button(action_or_type, action_type)
  return action_type == "ui_button"
    and type(action_or_type) == "table"
    and action_or_type.id == "auto"
end

local function _has_active_modal_state(gate_state)
  return gate_state.choice_active
    or gate_state.market_active
    or gate_state.popup_active
    or gate_state.detained_wait_active
end

local function _is_next_button_in_active_state(action_or_type, action_type, gate_state)
  if action_type ~= "ui_button" then return false end
  if type(action_or_type) ~= "table" then return false end
  if action_or_type.id ~= "next" then return false end
  return _has_active_modal_state(gate_state)
end

local _GATE_FLAG_KEYS = {
  "input_blocked",
  "choice_active",
  "market_active",
  "popup_active",
  "detained_wait_active",
}

local function _normalize_gate_flags(source)
  local gate_state = {}
  for _, key in ipairs(_GATE_FLAG_KEYS) do
    gate_state[key] = source[key] == true
  end
  gate_state.phase = source.phase
  return gate_state
end

function turn_action_gate.resolve_gate_state(gate_state_or_flag)
  if type(gate_state_or_flag) ~= "table" then
    return _normalize_gate_flags({ input_blocked = gate_state_or_flag == true })
  end
  return _normalize_gate_flags(gate_state_or_flag)
end

function turn_action_gate.should_block_action(gate_state_or_flag, action_or_type)
  local gate_state = turn_action_gate.resolve_gate_state(gate_state_or_flag)
  local action_type = _normalize_action_type(action_or_type)
  if _is_always_permitted(action_type) then return false end
  if _is_auto_button(action_or_type, action_type) then return false end
  if _is_next_button_in_active_state(action_or_type, action_type, gate_state) then return true end
  if not gate_state.input_blocked then return false end
  return not not input_blocked_types[action_type]
end

return turn_action_gate

