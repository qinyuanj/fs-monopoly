local role_context = require("src.ui.view.role_context")
local with_client_role = require("src.ui.render.support.with_client_role")
local runtime = require("src.ui.render.support.runtime_ui")
local canvas = require("src.ui.coord.canvas_coordinator")
local runtime_state = require("src.ui.state.runtime")
local modal_state = require("src.ui.state.modal")
local popup_assets = require("src.ui.coord.popup_assets")
local item_atlas_nodes = require("src.ui.schema.item_atlas")
local item_atlas_view = require("src.ui.render.widgets.item_atlas")
local role_id_utils = require("src.foundation.identity")

local renderer = {}

local function _is_popup_target(target_canvas)
  return target_canvas == canvas.CANVAS_POPUP or target_canvas == canvas.CANVAS_BANKRUPTCY
end

local function _broadcast_keeps_canvas(broadcast, target_canvas)
  return broadcast and _is_popup_target(target_canvas)
end

local function _resolve_modal_canvas_for_ctx(ctx, kind, target_canvas, fallback_canvas, broadcast)
  if _broadcast_keeps_canvas(broadcast, target_canvas) then
    return target_canvas
  end
  if ctx and ctx.can_operate == true then
    return target_canvas
  end
  if kind == "bankruptcy" then
    return target_canvas
  end
  return fallback_canvas
end

-- 旁观者回屏按「关闭时刻」的面板态重解析(与 resolve_canvas_after_popup 的回屏
-- 原则一致,不做开屏快照):展示期间面板被其它流程关掉时,回基础屏而不是过期画面。
-- 面板→canvas 映射住 canvas_coordinator(#583 起与黑市开屏分道共用一份)。
local function _resolve_bystander_return_canvas(state, role_id)
  local ui = state and state.ui
  return canvas.resolve_role_panel_canvas(ui, role_id) or canvas.CANVAS_BASE
end

local function _switch_canvas_for_role(ui, role, target)
  if role then
    canvas.switch_for_role(ui, target, role)
  else
    canvas.switch(ui, target)
  end
end

local function _resolve_role_id(ctx, role)
  return ctx and ctx.role_id or runtime.resolve_role_id(role)
end

-- 旁观者兜底 canvas:仅广播关闭弹窗且操作者本人不开时,把旁观角色切回
-- 其返回 canvas;条件不齐时返回 nil,调用方沿用已解析 canvas。
local function _resolve_bystander_canvas(state, ctx, role, switch_ctx)
  if not (switch_ctx.broadcast and not switch_ctx.is_opening) then
    return nil
  end
  local role_id = _resolve_role_id(ctx, role)
  if role_id == nil or role_id_utils.equals(role_id, switch_ctx.operator_role_id) then
    return nil
  end
  return _resolve_bystander_return_canvas(state, role_id)
end

-- #583:旁观者回图鉴屏前清掉陈旧放大卡——放大覆盖层三节点住图鉴 canvas,
-- 不清理会随回屏复活/滞留。本函数在 with_client_role 扇出内被调,覆盖层
-- 显隐按 per-role 落到该旁观者客户端。
local function _clear_stale_atlas_enlarged(state)
  local atlas = state.ui and state.ui.item_atlas
  if type(atlas) ~= "table" then
    return
  end
  atlas.selected_item_id = nil
  item_atlas_view.hide_enlarged(state)
end

-- 买家免展示口径(2026-08-25):载荷排除的角色(黑市买家)开屏不切去弹窗、
-- 收屏也不回切——其 canvas 全程未离开(黑市屏不动),任何切换都是多余抖动。
-- #604 例外:switch_ctx.excluded_return(choice 收屏路径)下买家黑市已随 choice
-- 关闭,不能再整体跳过——切回其返回 canvas(面板或基础屏),否则「隐藏黑市屏」
-- 事件永远不发,客户端屏滞留到无关 canvas 切换。
local function _is_excluded_role(switch_ctx, ctx, role)
  if switch_ctx.exclude_role_id == nil then
    return false
  end
  local role_id = _resolve_role_id(ctx, role)
  return role_id ~= nil and role_id_utils.equals(role_id, switch_ctx.exclude_role_id)
end

local function _return_excluded_role(state, role, ctx)
  local role_id = _resolve_role_id(ctx, role)
  if role_id == nil then
    return
  end
  _switch_canvas_for_role(state.ui, role, _resolve_bystander_return_canvas(state, role_id))
end

-- 排除角色的弹窗期处置:默认整体跳过(其 canvas 全程未离开),仅 excluded_return
-- 时补回切。返回 true 表示该角色的切换已由排除口径决定,调用方不再往下走。
local function _switch_excluded_role(state, role, ctx, switch_ctx)
  if not _is_excluded_role(switch_ctx, ctx, role) then
    return false
  end
  if switch_ctx.excluded_return then
    _return_excluded_role(state, role, ctx)
  end
  return true
end

-- #202:下一屏解析成基础屏时,操作者本人回自己开着的面板 canvas(#583 口径),
-- 没开面板才真回基础屏。骰子 / 选择屏 / 黑市保持原逻辑,操作者面板不抢这些屏;
-- 只按操作者身份生效,破产弹窗这类「target 对全员生效」的分支也不会把旁观者
-- 带去操作者的面板 canvas。
local function _resolve_operator_return_canvas(state, ctx, role, switch_ctx, resolved)
  if resolved ~= canvas.CANVAS_BASE then
    return resolved
  end
  local role_id = _resolve_role_id(ctx, role)
  if not role_id_utils.equals(role_id, switch_ctx.operator_role_id) then
    return resolved
  end
  return canvas.resolve_role_panel_canvas(state.ui, role_id) or resolved
end

-- 该角色最终要切的 canvas:旁观者回屏优先(回图鉴屏先清陈旧放大卡),
-- 否则沿用已解析的弹窗 canvas。
local function _resolve_switch_canvas(state, ctx, role, switch_ctx, resolved)
  local target = _resolve_bystander_canvas(state, ctx, role, switch_ctx)
    or _resolve_operator_return_canvas(state, ctx, role, switch_ctx, resolved)
  if target == item_atlas_nodes.canvas then
    _clear_stale_atlas_enlarged(state)
  end
  return target
end

local function _resolve_and_switch_for_role(state, role, switch_ctx)
  local current_model = runtime_state.get_ui_model(state)
  local ctx = role_context.resolve(role, current_model, { runtime = runtime })
  if _switch_excluded_role(state, role, ctx, switch_ctx) then
    return
  end
  local resolved = _resolve_modal_canvas_for_ctx(ctx, switch_ctx.kind, switch_ctx.target_canvas, switch_ctx.fallback_canvas, switch_ctx.broadcast)
  if resolved == nil then
    return
  end
  _switch_canvas_for_role(state.ui, role, _resolve_switch_canvas(state, ctx, role, switch_ctx, resolved))
end

function renderer.switch_popup_canvas(state, kind, target_canvas, fallback_canvas, opts)
  local ui = state.ui
  local switch_ctx = {
    kind = kind,
    target_canvas = target_canvas,
    fallback_canvas = fallback_canvas,
    broadcast = ui and ui.popup_broadcast == true,
    exclude_role_id = ui and ui.popup_exclude_role_id or nil,
    excluded_return = opts ~= nil and opts.excluded_return == true,
    is_opening = _is_popup_target(target_canvas),
    operator_role_id = modal_state.operator_role_id(state),
  }

  runtime.for_each_role_or_global(function(role)
    with_client_role(runtime, role, function()
      _resolve_and_switch_for_role(state, role, switch_ctx)
    end)
  end)
  runtime.set_client_role(nil)
end

local function _render_bankruptcy_popup(state, payload)
  local ui = state.ui
  local screen = ui.bankruptcy_screen
  renderer.switch_popup_canvas(state, "bankruptcy", canvas.CANVAS_BANKRUPTCY, nil)
  if screen and screen.text then
    ui:set_label(screen.text, popup_assets.resolve_bankruptcy_text(payload))
  end
  popup_assets.set_bankruptcy_avatar_image(state, payload)
  -- #178:破产屏只自动关闭、不接点背景关闭,隐藏"点击背景关闭"提示。
  if screen and screen.close_hint then
    ui:set_visible(screen.close_hint, false)
  end
  if screen and screen.root then
    ui:set_visible(screen.root, true)
  end
end
local function _render_card_popup(state, kind, payload)
  local ui = state.ui
  local popup = ui.popup_screen
  renderer.switch_popup_canvas(state, kind, canvas.CANVAS_POPUP, nil)
  ui:set_label(popup.title, payload.title)
  popup_assets.set_popup_card_image(state, payload)
  if popup and popup.root then
    ui:set_visible(popup.root, true)
  end
end
function renderer.show_popup(state, payload)
  local ui = state.ui
  -- kind 缺省(nil)与 "card" 同走卡牌分支;popup_kind 的三个读者
  -- (本文件 _hide_popup、popup_presenter、modal)对 nil 各自回落卡牌,
  -- 这里的 `or "card"` 与 _hide_popup 的成对死防御(#262 删除)。
  local kind = payload.kind
  ui.popup_kind = kind
  if kind == "bankruptcy" then
    _render_bankruptcy_popup(state, payload)
  else
    _render_card_popup(state, kind, payload)
  end
  popup_assets.set_popup_dismiss_touch(ui, true)
end

renderer.show = renderer.show_popup
local function _hide_bankruptcy_popup(state)
  local ui = state.ui
  local screen = ui.bankruptcy_screen
  if screen and screen.root then
    ui:set_visible(screen.root, false)
  end
  popup_assets.set_bankruptcy_avatar_image(state, nil)
end
local function _hide_card_popup(state)
  local ui = state.ui
  if ui.popup_screen and ui.popup_screen.root then
    ui:set_visible(ui.popup_screen.root, false)
  end
  popup_assets.set_popup_card_image(state, nil)
end
local function _hide_popup(state)
  local ui = state.ui
  if ui.popup_kind == "bankruptcy" then
    _hide_bankruptcy_popup(state)
  else
    _hide_card_popup(state)
  end
  popup_assets.set_popup_dismiss_touch(ui, false)
end

renderer.hide = _hide_popup

return renderer

