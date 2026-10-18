local role_context = require("src.ui.view.role_context")
local panel_cash_delta = require("src.ui.render.widgets.cash_delta")
local panel_player_slots = require("src.ui.render.widgets.player_slots")
local panel_controls = require("src.ui.render.widgets.panel_controls")
local market_view_controls = require("src.ui.render.market.controls")
local ui_touch_policy_runtime = require("src.ui.input.touch")
local runtime_assets = require("src.config.runtime_assets")

local panel_presenter = {}
local _role_ctx_opts = {}
local _item_slot_opts = {}

local function _refresh_for_role(state, ui_model, runtime, role, panel, refresh_item_slots, ui_touch_policy)
  local ui = state.ui
  _role_ctx_opts.runtime = runtime
  local ctx = role_context.resolve(role, ui_model, _role_ctx_opts)
  local base_visible = panel_controls.is_base_non_player_visible(ui, ctx)
  panel_controls.apply_base_non_player_visibility(ui, base_visible)
  local skin_visible = panel_controls.resolve_skin_entry_visible(ui_model, ctx)
  panel_controls.apply_skin_entry_visibility(ui, skin_visible)
  panel_player_slots.force_item_slots_visible_for_player(ui, ctx)
  panel_controls.apply_auto_effect(ui, ui_model, ctx)
  panel_controls.apply_countdown(ui, panel)
  -- 黑市打开期间整帧渲染不走每秒滴答的窄路,黑市屏倒计时在这里同步首帧与脏渲染
  market_view_controls.apply_market_countdown(ui, panel.turn_label, panel.countdown_visible)
  panel_controls.apply_action_hint(ui, panel)
  panel_controls.apply_base_action_controls(ui, ui_model, base_visible,
    panel_controls.is_base_cancel_allowed(ui, ctx))
  _item_slot_opts.role_id = ctx.role_id
  _item_slot_opts.display_player_id = ctx.display_player_id
  _item_slot_opts.allow_interact = panel_controls.is_slot_touch_allowed(ui)
  refresh_item_slots(state, ui_model, _item_slot_opts)
  panel_controls.render_auto_controls_for_role(ui, ctx, ui_model, ui_touch_policy)
  return ctx
end

local function _resolve_presentation_runtime_policy(state)
  return state and state.presentation_runtime and state.presentation_runtime.ui_touch_policy
end

local function _resolve_ui_touch_policy(state, deps)
  return deps.ui_touch_policy
    or _resolve_presentation_runtime_policy(state)
    or ui_touch_policy_runtime
end

local function _resolve_refresh_deps(state, deps)
  local runtime = assert(deps.runtime, "missing deps.runtime")
  local refresh_item_slots = assert(deps.refresh_item_slots, "missing deps.refresh_item_slots")
  local ui_touch_policy = _resolve_ui_touch_policy(state, deps)
  assert(ui_touch_policy, "missing deps.ui_touch_policy")
  return runtime, refresh_item_slots, ui_touch_policy
end

local function _empty_avatar_key(state)
  local image = runtime_assets.empty_image(runtime_assets.asset_context(state))
  return image.image_key
end

local function _panel_players(ui_model)
  local board = ui_model.board or {}
  return board.players or {}
end

local function _render_player_slots(ui, runtime, panel, empty_avatar_key)
  local player_rows = panel.player_rows or {}
  for i = 1, 4 do
    panel_player_slots.render_player_slot(
      ui,
      runtime,
      player_rows[i],
      i,
      empty_avatar_key,
      panel_cash_delta.refresh_cash_delta_label
    )
  end
  panel_player_slots.refresh_player_crowns(ui, player_rows)
end

local _rar_state
local _rar_ui_model
local _rar_runtime
local _rar_panel
local _rar_refresh_item_slots
local _rar_ui_touch
local _rar_players

local function _refresh_all_roles_callback(role)
  _refresh_for_role(_rar_state, _rar_ui_model, _rar_runtime, role, _rar_panel, _rar_refresh_item_slots, _rar_ui_touch)
  for i = 1, 4 do
    panel_player_slots.apply_player_colors(role, _rar_runtime, _rar_players[i], i)
  end
end

local function _refresh_all_roles(state, ui_model, runtime, panel, refresh_item_slots, ui_touch_policy, players)
  _rar_state = state
  _rar_ui_model = ui_model
  _rar_runtime = runtime
  _rar_panel = panel
  _rar_refresh_item_slots = refresh_item_slots
  _rar_ui_touch = ui_touch_policy
  _rar_players = players
  runtime.for_each_role_or_global(_refresh_all_roles_callback)
  _rar_state = nil
  _rar_ui_model = nil
  _rar_runtime = nil
  _rar_panel = nil
  _rar_refresh_item_slots = nil
  _rar_ui_touch = nil
  _rar_players = nil
end

function panel_presenter.refresh(state, ui_model, deps)
  assert(state ~= nil and state.ui ~= nil, "missing state.ui")
  assert(ui_model ~= nil and ui_model.panel ~= nil, "missing ui_model.panel")
  assert(deps ~= nil, "missing deps")
  local runtime, refresh_item_slots, ui_touch_policy = _resolve_refresh_deps(state, deps)
  local ui = state.ui
  local panel = ui_model.panel
  local players = _panel_players(ui_model)
  local empty_avatar_key = _empty_avatar_key(state)
  runtime.set_client_role(nil)
  panel_cash_delta.ensure_state(ui)
  _render_player_slots(ui, runtime, panel, empty_avatar_key)
  _refresh_all_roles(state, ui_model, runtime, panel, refresh_item_slots, ui_touch_policy, players)
  runtime.set_client_role(nil)
end
return panel_presenter

