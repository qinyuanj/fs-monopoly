local market_layout = require("src.ui.schema.market_layout")
local ui_controls = require("src.ui.render.support.ui_controls")
local runtime_state = require("src.ui.state.runtime")
local market_view_slots = require("src.ui.render.market.slots")
local market_view_controls = require("src.ui.render.market.controls")
local runtime_ui = require("src.ui.render.support.runtime_ui")
local runtime_assets = require("src.config.runtime_assets")
local number_utils = require("src.foundation.number")

local market_view = {}

local function _fallback_modal_state()
  return {
    open_market = function(state, choice_id, option_ids, selected_option_id)
      runtime_state.set_pending_choice_id(state, choice_id)
      local ui_runtime = runtime_state.ensure_ui_runtime(state)
      ui_runtime.choice_visible_option_ids = option_ids
      ui_runtime.pending_choice_selected_option_id = selected_option_id
    end,
    select_market_option = function(state, option_id)
      runtime_state.ensure_ui_runtime(state).pending_choice_selected_option_id = option_id
    end,
    close_choice = function(state)
      local ui_runtime = runtime_state.ensure_ui_runtime(state)
      ui_runtime.choice_visible_option_ids = nil
      ui_runtime.pending_choice_selected_option_id = nil
    end,
  }
end

local function _resolve_deps(state, deps)
  if deps then
    return deps
  end
  if state and state.presentation_runtime then
    return state.presentation_runtime
  end
  return {
    runtime = runtime_ui,
  }
end

local function _set_market_preview_icon(state, icon_key, deps)
  if icon_key == nil then
    return
  end
  local resolved_deps = _resolve_deps(state, deps)
  local runtime = assert(resolved_deps.runtime, "missing deps.runtime")
  local ui = state.ui
  runtime.set_node_texture_keep_size(ui.query_node(market_layout.selected_card), icon_key)
end

function market_view.refresh_market_selection(state, option_id, deps)
  local ui = state.ui
  assert(ui ~= nil, "missing market ui")
  local selection = market_view_slots.resolve_selection(
    option_id,
    runtime_assets.asset_context(state)
  )
  ui:set_label(market_layout.price_label, selection.price_text)
  _set_market_preview_icon(state, selection.icon_key, deps)
end

function market_view.select_market_option(state, option_id, deps)
  local resolved_deps = _resolve_deps(state, deps)
  local resolved_modal = resolved_deps.modal_state or _fallback_modal_state()
  resolved_modal.select_market_option(state, option_id)
  local ui_runtime = runtime_state.ensure_ui_runtime(state)
  market_view_controls.refresh_market_selection_frames(
    state.ui,
    ui_runtime.choice_visible_option_ids,
    option_id
  )
  market_view.refresh_market_selection(state, option_id, resolved_deps)
  market_view_controls.set_confirm_button_state(state.ui, true)
end

local function _current_cash_amount(state)
  local ui_model = runtime_state.get_ui_model(state)
  return ui_model and ui_model.current_player_cash or 0
end

local function _resolve_cash_display(state)
  local ui = state and state.ui or nil
  if not ui then
    return nil, nil
  end
  return ui, _current_cash_amount(state)
end

function market_view.refresh_cash_display(state)
  local ui, amount = _resolve_cash_display(state)
  if not ui then
    return
  end
  local text = number_utils.format_integer_part(amount)
  if ui.set_label then
    ui:set_label(market_layout.cash_text_label, "现金")
    ui:set_label(market_layout.cash_amount_label, text)
  end
  ui_controls.set_controls_state(ui, {
    market_layout.cash_text_label,
    market_layout.cash_amount_label,
    market_layout.cash_icon,
    market_layout.cash_background,
  }, { visible = true, touch_enabled = false })
end

local function _refresh_empty_market(state, market, resolved_deps, resolved_modal, ui)
  market_view_slots.hide_market_slots(ui)
  market_view_controls.reset_market_preview(state, resolved_deps)
  market_view_controls.apply_market_common_controls(ui, market, false)
  resolved_modal.open_market(state, market.choice_id, {}, nil)
  market_view.refresh_cash_display(state)
end

local function _refresh_populated_market(state, market, resolved_deps, resolved_modal, options, ui, was_market_active)
  local rendered = market_view_slots.populate_market_slots(ui, options)
  ui_controls.set_control_state(ui, market_layout.selected_card, { touch_enabled = false })
  market_view_controls.clear_market_selection_frames(ui)
  market_view_controls.apply_market_common_controls(ui, market, true)
  local selected_option_id = was_market_active and market.selected_option_id or nil
  local selected = market_view_slots.resolve_selected_option(
    rendered.option_ids,
    selected_option_id,
    rendered.first_buyable
  )
  resolved_modal.open_market(state, market.choice_id, rendered.option_ids, selected)
  market_view.select_market_option(state, selected, resolved_deps)
  market_view.refresh_cash_display(state)
end

function market_view.refresh_market(state, market, deps)
  local resolved_deps = _resolve_deps(state, deps)
  local resolved_modal = resolved_deps.modal_state or _fallback_modal_state()
  local ui = state.ui
  assert(market ~= nil and market.options ~= nil and ui ~= nil, "missing market data/ui")
  local was_market_active = ui.market_active == true
  local options = market_view_slots.filter_market_options(market.options)
  market_view_controls.set_market_container_active(ui, true)
  if #options == 0 then
    _refresh_empty_market(state, market, resolved_deps, resolved_modal, ui)
  else
    _refresh_populated_market(state, market, resolved_deps, resolved_modal, options, ui, was_market_active)
  end
  return true
end

function market_view.close_market_panel(state, deps)
  local resolved_deps = _resolve_deps(state, deps)
  local resolved_modal = resolved_deps.modal_state or _fallback_modal_state()
  local ui = state.ui
  assert(ui ~= nil and ui.market_active == true, "market panel not active")
  resolved_modal.close_choice(state)
  market_view_controls.close_market_panel(state, resolved_deps)
end

return market_view

