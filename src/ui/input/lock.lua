local market_ui = require("src.ui.schema.market_layout")
local base_nodes = require("src.ui.schema.base")
local ui_touch_policy = require("src.ui.input.touch")

local lock_policy = {}

local INPUT_LOCK_VISIBILITY_EXEMPT_NODES = {
  [base_nodes.auto_button] = true,
  [base_nodes.auto_label] = true,
  [base_nodes.action_log_button] = true,
  [base_nodes.skin_button] = true,
  [base_nodes.skin_label] = true,
  [base_nodes.gallery_button] = true,
}

local BASE_AUXILIARY_TOUCH_NODES = {
  base_nodes.skin_button,
  base_nodes.gallery_button,
  base_nodes.share_button,
}

local function _set_node_visible_unless_exempt(ui, name, visible)
  if not INPUT_LOCK_VISIBILITY_EXEMPT_NODES[name] then
    ui:set_visible(name, visible == true)
  end
end

local function _set_base_hidden_nodes_visible(ui, visible)
  if not ui or not ui.set_visible then
    return
  end
  local nodes = ui.base_hidden_nodes or {}
  for _, name in ipairs(nodes) do
    _set_node_visible_unless_exempt(ui, name, visible)
  end
end

local function _set_base_auxiliary_touch(ui, enabled)
  ui_touch_policy.set_auto_controls_touch(ui, enabled)
  ui_touch_policy.set_action_log_toggle_touch(ui, enabled)
  ui_touch_policy.set_many_touch_enabled(ui, BASE_AUXILIARY_TOUCH_NODES, enabled)
  ui_touch_policy.set_share_decor_touch(ui)
end

local function _apply_unlocked_state(ui, allow_always_show_touch)
  _set_base_auxiliary_touch(ui, allow_always_show_touch)
end

local function _lock_choice_screens(ui)
  local screens = ui.choice_screens or {}
  ui_touch_policy.set_choice_screen_locked(ui, screens.player)
  ui_touch_policy.set_choice_screen_locked(ui, screens.target)
  ui_touch_policy.set_choice_screen_locked(ui, screens.remote)
  ui_touch_policy.set_choice_screen_locked(ui, screens.building)
end

local function _set_market_cancel_touch(ui, enabled)
  local cancel_buttons = market_ui.cancel_buttons or {}
  ui_touch_policy.set_many_touch_enabled(ui, cancel_buttons, enabled)
end

local function _lock_market_buttons(ui, allow_cancel)
  ui_touch_policy.set_many_touch_enabled(ui, market_ui.item_buttons or {}, false)
  if market_ui.confirm_button then
    ui:set_touch_enabled(market_ui.confirm_button, false)
  end
  _set_market_cancel_touch(ui, allow_cancel == true)
end

-- 输入锁不关道具槽 touch：槽位是「全时段可点、点了必有反馈」口径(#162),
-- 移动动画等阶段位里点卡应当拿到「现阶段该卡无法使用」,而不是零反应。
-- 点击本身不会推进状态——item_slot_click 在 turn 闸上豁免,裁定后要么发提示
-- 要么转成 choice_select 再过一次闸。
local function _apply_locked_state(ui, allow_always_show_touch)
  _set_base_hidden_nodes_visible(ui, false)
  for _, slot_name in ipairs(ui.item_slots or {}) do
    ui:set_visible(slot_name, true)
  end
  ui:set_touch_enabled(base_nodes.action_button, false)
  ui:set_touch_enabled(base_nodes.end_button, false)
  _lock_choice_screens(ui)
  _lock_market_buttons(ui, ui.market_active == true)
  _set_base_auxiliary_touch(ui, allow_always_show_touch)
end

function lock_policy.apply(state, deps)
  assert(state ~= nil and state.ui ~= nil, "missing state.ui")
  assert(deps ~= nil, "missing deps")
  local ui = state.ui
  local allow_always_show_touch = ui.market_active ~= true

  if not ui.set_touch_enabled then
    return
  end

  if not ui.input_blocked then
    _apply_unlocked_state(ui, allow_always_show_touch)
    return
  end

  _apply_locked_state(ui, allow_always_show_touch)
end

return lock_policy

