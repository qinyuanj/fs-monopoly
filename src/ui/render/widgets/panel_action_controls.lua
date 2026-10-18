local base_nodes = require("src.ui.schema.base")
local choice_support = require("src.ui.view.choice_support")

local panel_action_controls = {}

local function _resolve_countdown_visible(panel)
  if panel and panel.countdown_visible ~= nil then
    return panel.countdown_visible == true
  end
  return true
end

function panel_action_controls.apply_countdown(ui, panel)
  local visible = _resolve_countdown_visible(panel)
  ui:set_visible(base_nodes.countdown, visible)
  ui:set_visible(base_nodes.countdown_line, visible)
  ui:set_label(base_nodes.countdown, panel.turn_label or "")
end

function panel_action_controls.apply_action_hint(ui, panel)
  if panel.no_action_visible == true then
    ui:set_visible(base_nodes.action_hint, true)
  end
end

-- Which of 行动 / 结束 owns an optional-action choice depends on the phase the
-- choice sits in: pre-action skips belong to 行动 (they precede the roll),
-- everything else resolves through 结束; a forced choice offers no way out.
local function _optional_action_visibility(choice)
  if not choice_support.is_optional_action_choice(choice) then
    return true, false, false
  end
  if not choice_support.is_cancelable_optional_action_choice(choice) then
    return false, false, false
  end
  if choice_support.is_pre_action_item_phase_passive(choice) then
    return true, false, false
  end
  return false, true, false
end

local function _resolve_base_action_visibility(ui_model, base_visible, cancel_allowed)
  local choice = ui_model and ui_model.choice
  -- Item usage follow-up (道具使用后续选择, kind varies per card, truth source is
  -- rules' meta.passive_origin): the base cancel button is the ONLY exit back to
  -- the item phase window without consuming the card. The follow-up's own screen
  -- sets choice_active, which drops base_visible for the whole base screen, so
  -- the cancel button runs on its own narrow gate (cancel_allowed, computed by
  -- panel_controls.is_base_cancel_allowed: every interruption EXCEPT the choice
  -- itself still blocks). is_base_cancel_choice is the same gate route_base
  -- builds the cancel intent from: 按钮亮即有 intent。
  if choice_support.is_item_target_selection_choice(choice) then
    return false, false, cancel_allowed == true and choice_support.is_base_cancel_choice(choice)
  end
  if base_visible ~= true then
    return false, false, false
  end
  return _optional_action_visibility(choice)
end

function panel_action_controls.apply_base_action_controls(ui, ui_model, base_visible, cancel_allowed)
  local action_visible, end_visible, cancel_visible =
    _resolve_base_action_visibility(ui_model, base_visible, cancel_allowed)
  ui:set_visible(base_nodes.action_button, action_visible)
  ui:set_touch_enabled(base_nodes.action_button, action_visible)
  ui:set_visible(base_nodes.end_button, end_visible)
  ui:set_touch_enabled(base_nodes.end_button, end_visible)
  ui:set_visible(base_nodes.cancel_button, cancel_visible)
  ui:set_touch_enabled(base_nodes.cancel_button, cancel_visible)
end

return panel_action_controls

