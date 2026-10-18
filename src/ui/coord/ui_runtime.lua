local panel_presenter = require("src.ui.render.widgets.presenter")
local board_runtime = require("src.ui.render.board")
local turn_effects = require("src.ui.render.widgets.turn_effects")
local render_pipeline = require("src.ui.render.support.render_pipeline")
local input_lock_policy = require("src.ui.input.lock")
local role_control_lock_policy = require("src.ui.input.role_control_lock")
local ui_touch_policy = require("src.ui.input.touch")
local runtime = require("src.ui.render.support.runtime_ui")
local schema_base_nodes = require("src.ui.schema.base")
local market_view_controls = require("src.ui.render.market.controls")

local state = require("src.ui.coord.ui_state")
local assets = require("src.ui.render.support.assets")
local item_slots = require("src.ui.coord.item_slots")
local event_log_view = require("src.ui.coord.event_log_view")

local service = {}

-- #329:render_pipeline 的三个刷新实现由装配侧(本协调器)注入,支持层不再
-- 静态 require 下游。
local _render_opts = {
  panel = panel_presenter,
  board = board_runtime,
  effects = turn_effects,
  runtime = runtime,
  refresh_item_slots = nil,
  ui_touch_policy = ui_touch_policy,
}
local _input_lock_opts = { runtime = runtime }
local _role_control_opts = { runtime = runtime }

local turn_label_refresh_context = {
  ui = nil,
  base_nodes = nil,
  label_text = nil,
  countdown_visible = nil,
}

service.build_ui_state = state.build_ui_state
service.init_ui_assets = assets.init_ui_assets
service.capture_player_colors = assets.capture_player_colors

-- 行为测试公共接缝：角色槽位、触摸与演出场景经完整面板刷新观察可见结果。
function service.refresh_panel(state_ctx, ui_model)
  _render_opts.refresh_item_slots = service.refresh_item_slots
  panel_presenter.refresh(state_ctx, ui_model, _render_opts)
end

local function _refresh_turn_label_for_runtime_role(ui, base_nodes, label_text, countdown_visible)
  if ui.set_visible then
    ui:set_visible(base_nodes.countdown, countdown_visible)
    ui:set_visible(base_nodes.countdown_line, countdown_visible)
  end
  if ui.set_label then
    ui:set_label(base_nodes.countdown, label_text)
  end
  -- 黑市屏倒计时镜像:每秒滴答只走这条窄路,不经过 presenter,必须在这里同步
  market_view_controls.apply_market_countdown(ui, label_text, countdown_visible)
end

local function _refresh_turn_label_for_client_role()
  local ui = turn_label_refresh_context.ui
  local base_nodes = turn_label_refresh_context.base_nodes
  local label_text = turn_label_refresh_context.label_text
  local countdown_visible = turn_label_refresh_context.countdown_visible
  if ui ~= nil and base_nodes ~= nil then
    _refresh_turn_label_for_runtime_role(ui, base_nodes, label_text, countdown_visible)
  end
end

local function _clear_turn_label_refresh_context()
  turn_label_refresh_context.ui = nil
  turn_label_refresh_context.base_nodes = nil
  turn_label_refresh_context.label_text = nil
  turn_label_refresh_context.countdown_visible = nil
end

function service.refresh_turn_label(state_ctx, label_text, visible)
  local ui = state_ctx.ui
  if not ui then
    return
  end
  local countdown_visible = visible ~= false

  turn_label_refresh_context.ui = ui
  turn_label_refresh_context.base_nodes = schema_base_nodes
  turn_label_refresh_context.label_text = label_text
  turn_label_refresh_context.countdown_visible = countdown_visible

  runtime.for_each_role_or_global(_refresh_turn_label_for_client_role)

  _clear_turn_label_refresh_context()
  runtime.set_client_role(nil)
end

service.refresh_item_slots = item_slots.refresh_item_slots

function service.apply_input_lock(state_ctx)
  input_lock_policy.apply(state_ctx, _input_lock_opts)
end

function service.apply_role_control_lock(state_ctx, enabled)
  role_control_lock_policy.sync(state_ctx, enabled, _role_control_opts)
end

function service.render(state_ctx, ui_model, log_once, build_log_prefix)
  _render_opts.refresh_item_slots = service.refresh_item_slots
  render_pipeline.render(state_ctx, ui_model, log_once, build_log_prefix, _render_opts)
end

service.set_event_log = event_log_view.set_event_log
service.set_event_log_visible = event_log_view.set_event_log_visible
service.set_event_log_visible_for_role = event_log_view.set_event_log_visible_for_role
service.set_event_log_for_role = event_log_view.set_event_log_for_role

return service

