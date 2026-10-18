local base_nodes = require("src.ui.schema.base")
local role_id_utils = require("src.foundation.identity")
local ui_touch_policy_runtime = require("src.ui.input.touch")
local panel_interrupt = require("src.ui.state.panel_interrupt")
local panel_action_controls = require("src.ui.render.widgets.panel_action_controls")

local panel_controls = {}

panel_controls.apply_countdown = panel_action_controls.apply_countdown
panel_controls.apply_action_hint = panel_action_controls.apply_action_hint
panel_controls.apply_base_action_controls = panel_action_controls.apply_base_action_controls

local function _set_visible_many(ui, names, visible)
  for _, name in ipairs(names or {}) do
    ui:set_visible(name, visible)
  end
end

function panel_controls.apply_base_non_player_visibility(ui, visible)
  assert(ui ~= nil, "missing ui")
  local value = visible == true
  _set_visible_many(ui, ui.base_hidden_nodes, value)
  _set_visible_many(ui, ui.base_hidden_labels, value)
end

local function _resolve_auto_label(panel, display_player_id)
  if panel == nil then
    return nil
  end
  local labels_by_player = panel.auto_label_by_player
  if labels_by_player ~= nil and display_player_id ~= nil then
    local auto_label = labels_by_player[display_player_id]
    if auto_label then
      return auto_label
    end
  end
  return panel.auto_label
end

local function _apply_auto_label(ui, panel, display_player_id)
  local auto_label = _resolve_auto_label(panel, display_player_id)
  if auto_label == nil or not ui.set_label then
    return
  end
  ui:set_label(base_nodes.auto_label, auto_label)
end

local function _show_auto_controls(ui, controls)
  for _, name in ipairs(controls) do
    ui:set_visible(name, true)
  end
end

local function _resolve_auto_controls(ui)
  return ui.auto_control_nodes or { base_nodes.auto_button, base_nodes.auto_label }
end

local function _is_player_role(ctx)
  return ctx.is_player_role == true
end

function panel_controls.render_auto_controls_for_role(ui, ctx, ui_model, ui_touch_policy)
  assert(ui ~= nil, "missing ui")
  local controls = _resolve_auto_controls(ui)
  local panel = ui_model and ui_model.panel or nil
  _apply_auto_label(ui, panel, ctx.display_player_id)
  _show_auto_controls(ui, controls)
  ui_touch_policy.set_auto_controls_touch(ui, _is_player_role(ctx), controls)
end

function panel_controls.is_base_non_player_visible(ui, ctx)
  if ui.input_blocked then
    return false
  end
  if panel_interrupt.settlement_type(ui) ~= nil then
    return false
  end
  return ctx.can_operate == true
end

-- 基础屏取消按钮的窄门(道具 followup 取消口径):followup 的选择屏开屏即置
-- choice_active,base_visible 整门必然落下,而取消按钮是该阶段唯一退出口——
-- 遮挡判定豁免 choice_active,其余(输入锁/弹窗/黑市/移动)与 per-role
-- can_operate 照常拦。
function panel_controls.is_base_cancel_allowed(ui, ctx)
  if ui.input_blocked then
    return false
  end
  if panel_interrupt.settlement_type_excluding_choice(ui) ~= nil then
    return false
  end
  return ctx.can_operate == true
end

-- 道具槽 touch 门的 allow_interact(#162 四次复验):语义是「无真弹层遮挡」。
-- input_blocked 与 move_active 是阶段位(他人回合墙钟几乎全程如此),不关此门;
-- 只有弹窗/黑市/机会覆盖弹层才关。base 其它控件维持 can_operate 口径。
function panel_controls.is_slot_touch_allowed(ui)
  return not panel_interrupt.is_overlay_visible(ui)
end

local function _auto_effect_role_id(ctx)
  if ctx.is_player_role ~= true then
    return nil
  end
  return ctx.role_id
end

local function _resolve_auto_effect_visible(ui_model, ctx)
  local role_id = _auto_effect_role_id(ctx)
  if role_id == nil then return false end
  local delegated_by_player = ui_model.delegated_by_player or {}
  return role_id_utils.read(delegated_by_player, role_id) == true
end

function panel_controls.apply_auto_effect(ui, ui_model, ctx)
  ui:set_visible(base_nodes.auto_effect, _resolve_auto_effect_visible(ui_model, ctx))
  ui:set_touch_enabled(base_nodes.auto_effect, false)
end

function panel_controls.resolve_skin_entry_visible(ui_model, ctx)
  local current_player_id = role_id_utils.normalize(ui_model.current_player_id)
  if current_player_id == nil then
    return false
  end
  return ctx.can_operate ~= true
end

function panel_controls.apply_skin_entry_visibility(ui, visible)
  local value = visible == true
  ui:set_visible(base_nodes.skin_button, value)
  ui:set_visible(base_nodes.skin_label, value)
  ui:set_touch_enabled(base_nodes.skin_button, value)
  ui:set_touch_enabled(base_nodes.skin_label, false)
  ui_touch_policy_runtime.set_many_touch_enabled(ui, base_nodes.skin_effect_nodes, false)
end

return panel_controls

