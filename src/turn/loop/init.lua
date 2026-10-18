local items_cfg = require("src.config.content.items")
local debug_flags = require("src.config.gameplay.debug_flags")
local timing = require("src.config.gameplay.timing")
local logger = require("src.foundation.log")
local turn_dispatch = require("src.turn.actions.action_dispatcher")
local gameplay_loop_ports = require("src.turn.loop.ports")
local gameplay_loop_runtime = require("src.turn.loop.runtime")
local intent_dispatcher = require("src.turn.output.intent_dispatcher")
local event_feed_adapter = require("src.turn.output.event_feed_adapter")
local auto_context = require("src.turn.policies.auto_context")
local afk_signal = require("src.turn.policies.afk_signal")
local turn_role_control_policy = require("src.turn.policies.role_control")
local deadlines = require("src.turn.deadlines")
local turn_anim = require("src.turn.output.anim")
local turn_timer_policy = require("src.turn.policies.timer")
local turn_camera_policy = require("src.turn.policies.camera")
local target_select_timer = require("src.turn.waits.target_select_timer")
local endgame = require("src.rules.endgame")
local paid_currency_bridge = require("src.rules.commerce.paid_currency_bridge")
local market_purchase = require("src.rules.market.purchase")
local runtime_state = require("src.state.runtime")
local player_control = require("src.player.control")
local player_control_snapshot = require("src.turn.output.player_control_snapshot")
local landing_visual_hold = require("src.state.visual_hold")
local wait_callbacks = require("src.turn.waits.callback_registry")
local blocking = require("src.turn.waits.blocking")
local wait_keys = wait_callbacks.wait_keys
local gameplay_loop = {}

local function _noop()
  return nil
end

local _default_is_computer_controlled = function(_, player)
  return player_control.is_computer_controlled(player)
end

local _auto_play_defaults = {
  is_computer_controlled = _default_is_computer_controlled,
  choose_action = _noop,
  auto_action_for_choice = _noop,
  pick_target_player = _noop,
  pick_remote_dice_value = _noop,
  pick_roadblock_target = _noop,
}

local _bankruptcy_defaults = {
  eliminate = _noop,
}

local function _fill_defaults(port, defaults)
  for name, fallback in pairs(defaults) do
    if type(port[name]) ~= "function" then
      port[name] = fallback
    end
  end
end

local function _ensure_fallback_ports(game)
  if type(game.auto_play_port) ~= "table" then
    game.auto_play_port = {}
  end
  _fill_defaults(game.auto_play_port, _auto_play_defaults)
  if type(game.bankruptcy_port) ~= "table" then
    game.bankruptcy_port = {}
  end
  _fill_defaults(game.bankruptcy_port, _bankruptcy_defaults)
end

local function _ensure_runtime_ports(game)
  if not game then
    return
  end
  if type(game.intent_output_port) ~= "table" then
    game.intent_output_port = intent_dispatcher.build_port()
  end
  _ensure_fallback_ports(game)
end

local function _has_input_lock_methods(ui_sync_ports)
  return ui_sync_ports.get_ui_state ~= nil and ui_sync_ports.is_input_blocked ~= nil
end

local function _should_apply_input_lock(ui_sync_ports, state, input_blocked_changed, ui_refreshed)
  return input_blocked_changed or (ui_sync_ports.is_input_blocked(state) and ui_refreshed)
end

local function _sync_input_lock(ui_sync_ports, state, input_blocked_changed, ui_refreshed)
  if not _has_input_lock_methods(ui_sync_ports) then return end
  local ui = ui_sync_ports.get_ui_state(state)
  if ui ~= nil and _should_apply_input_lock(ui_sync_ports, state, input_blocked_changed, ui_refreshed) then
    ui_sync_ports.apply_input_lock(state)
  end
end

local _move_anim_call_opts = { on_move_anim = nil }
local _action_anim_call_opts = { on_action_anim = nil }
local _cached_anim_ports_ref = nil
local function _ensure_anim_callbacks(anim_ports)
  if _cached_anim_ports_ref == anim_ports then return end
  _cached_anim_ports_ref = anim_ports
  _move_anim_call_opts.on_move_anim = function(s, anim_ctx) return anim_ports.play_move_anim(s, anim_ctx) end
  _action_anim_call_opts.on_action_anim = function(s, anim_ctx) return anim_ports.play_action_anim(s, anim_ctx) end
end

local function _step_phase_animation(game, state, phase, ports)
  local anim_ports = ports.anim
  if phase == "wait_move_anim" then
    if not game.turn.move_anim then return end
    _ensure_anim_callbacks(anim_ports)
    turn_anim.step_move_anim(game, state, _move_anim_call_opts)
  elseif phase == "wait_action_anim" then
    if not game.turn.action_anim then return end
    _ensure_anim_callbacks(anim_ports)
    turn_anim.step_action_anim(game, state, _action_anim_call_opts)
  end
end

local function _accumulate_game_time(game, dt)
  game.game_time_seconds = (game.game_time_seconds or 0) + (dt or 0)
end

local function _check_game_time_victory(game)
  if game.check_victory and endgame.game_time_reached(game) then
    game:check_victory()
  end
end

local function _step_game_clock(game, dt)
  if game.finished then return end
  _accumulate_game_time(game, dt)
  _check_game_time_victory(game)
end

local function _step_tick_timeouts(game, state, dt, ports, dispatch_action_with_close_choice)
  local ui_sync_ports = ports.ui_sync
  deadlines.tick(state, dt)
  target_select_timer.step(game, state, dt)
  ui_sync_ports.step_choice_timeout(game, state, dt)
  ui_sync_ports.step_modal_timeout(game, state, dt)
  local timer_ctx = state._action_timer_ctx or {}
  state._action_timer_ctx = timer_ctx
  timer_ctx.game, timer_ctx.state, timer_ctx.dt, timer_ctx.ports = game, state, dt, ports
  if timer_ctx._dispatch_ref ~= dispatch_action_with_close_choice then
    timer_ctx._dispatch_ref = dispatch_action_with_close_choice
    timer_ctx.dispatch_next = function(actor_role_id, input_source)
      timer_ctx._dispatch_ref(timer_ctx.game, timer_ctx.state, {
        type = "ui_button", id = "next", actor_role_id = actor_role_id, input_source = input_source,
      }, timer_ctx.ports)
    end
  end
  turn_timer_policy.update_action_button_timer(timer_ctx)
  turn_timer_policy.update_detained_wait_timer(game, state, dt, turn_dispatch.step_turn)
  turn_timer_policy.update_inter_turn_wait_timer(game, state, dt, turn_dispatch.step_turn)
end

local function _sync_tick_phase(game, state, ports, input_blocked_changed)
  local phase = game.turn.phase
  if gameplay_loop_runtime.sync_input_blocked(state, phase, ports) then input_blocked_changed = true end
  _step_phase_animation(game, state, phase, ports)
  gameplay_loop_runtime.sync_phase_flags(state, phase)
  return input_blocked_changed
end

local function _refresh_tick_from_dirty(game, state, ports, input_blocked_changed)
  local ui_sync_ports, anim_ports = ports.ui_sync, ports.anim
  ui_sync_ports.update_countdown(game, state)
  local dirty = game:consume_dirty()
  local release_pulse = runtime_state.take_landing_visual_release_pulse(state)
  if release_pulse then dirty.any, dirty.turn = true, true end
  local ui_refreshed = ui_sync_ports.refresh_from_dirty(game, state, dirty)
  if dirty.turn then turn_camera_policy.reset_follow(state) end
  turn_camera_policy.sync_follow(game, state, ports, ui_refreshed)
  if release_pulse or not landing_visual_hold.is_active_state(state) then anim_ports.sync_status_3d(game, state, dirty) end
  _sync_input_lock(ui_sync_ports, state, input_blocked_changed, ui_refreshed)
  ports.debug.sync_event_log(state)
end

local function _try_release_landing_visual(state, game)
  if not runtime_state.get_landing_visual_release_pending(state) then return false end
  local released = landing_visual_hold.release(state, game) == true
  if released then runtime_state.mark_landing_visual_release_pulse(state) end
  return released
end

local function _landing_visual_ready(game)
  local block = blocking.current_block(game)
  return block ~= nil and block.kind == "landing_visual"
    and wait_callbacks.is_wait_ready(game, wait_keys.landing_visual)
end

local function _maybe_advance_landing_visual(game)
  if game.advance_turn and _landing_visual_ready(game) then
    game:advance_turn()
  end
end

local function _tick_flow(game, state, dt, ports, deps)
  player_control_snapshot.install(game)
  _step_game_clock(game, dt)
  local released = _try_release_landing_visual(state, game)
  local input_blocked_changed = gameplay_loop_runtime.sync_input_blocked(state, game.turn.phase, ports)
  turn_role_control_policy.sync(game, state, ports)
  deps.step_auto_runner(game, state, dt, auto_context.build_tick(game, state, ports.ui_sync))
  _step_tick_timeouts(game, state, dt, ports, deps.dispatch_action_with_close_choice)
  input_blocked_changed = _sync_tick_phase(game, state, ports, input_blocked_changed)
  player_control_snapshot.install(game)
  _refresh_tick_from_dirty(game, state, ports, input_blocked_changed)
  -- #523 时序裁定（见 #524）：缺屏探针在 dirty 刷新之后采样，看到的是
  -- 同帧补偿开屏后的真实 open 状态，放行帧首开的窗口不再被误报。
  ports.ui_sync.probe_choice_ui_missing(game, state)
  if released then return end
  _maybe_advance_landing_visual(game)
end

local function _resolve_ports(state)
  if not state then
    return gameplay_loop_ports.resolve(nil)
  end
  local override = state.gameplay_loop_ports
  if state._resolved_gameplay_loop_ports and state._resolved_gameplay_loop_ports_source == override then
    return state._resolved_gameplay_loop_ports
  end
  local resolved = gameplay_loop_ports.resolve(override)
  state._resolved_gameplay_loop_ports = resolved
  state._resolved_gameplay_loop_ports_source = override
  state.gameplay_loop_ports = resolved
  return resolved
end
local _dispatch_opts = { on_close_choice = nil }
local _cached_modal_ports_ref = nil
local function _dispatch_action_with_close_choice(game, state, action, ports)
  local modal_ports = ports.modal
  if _cached_modal_ports_ref ~= modal_ports then
    _cached_modal_ports_ref = modal_ports
    _dispatch_opts.on_close_choice = function(ctx)
      modal_ports.close_choice_modal(ctx)
    end
  end
  turn_dispatch.dispatch_action(game, state, action, _dispatch_opts)
end
local function _build_item_index(state)
  local ui_runtime = runtime_state.ensure_ui_runtime(state)
  ui_runtime.item_name_by_id = {}
  for _, cfg in ipairs(items_cfg) do
    -- items 配置 19 条全有 name(配置真源钉死),「or tostring(cfg.id)」是恒被
    -- 短路的死默认——等价变异体,按 #257 三分类删冗余。
    ui_runtime.item_name_by_id[cfg.id] = cfg.name
  end
end
local function _popup_owner_supported(game, state, ui_sync_ports)
  return game ~= nil and state ~= nil and ui_sync_ports ~= nil and ui_sync_ports.get_popup_owner_index ~= nil
end

local function _popup_owner_index(ui_sync_ports, state)
  if ui_sync_ports.get_popup_owner_index then
    return ui_sync_ports.get_popup_owner_index(state)
  end
  return nil
end

local function _computer_popup_actor(game, idx)
  if idx and game.players then
    local actor = game.players[idx]
    return actor and player_control.is_computer_controlled(actor) or false
  end
  return false
end

local function _is_computer_popup_owner(game, state)
  local ports = _resolve_ports(state)
  local ui_sync_ports = ports.ui_sync
  if not _popup_owner_supported(game, state, ui_sync_ports) then
    return false
  end
  local idx = _popup_owner_index(ui_sync_ports, state)
  return _computer_popup_actor(game, idx)
end

local function _min_popup_visible_seconds()
  return timing.auto_decision_delay_seconds or 0
end

local function _is_computer_popup_waiting(game, state, ui_sync_ports)
  local min_popup_visible = _min_popup_visible_seconds()
  if min_popup_visible <= 0 then
    return false
  end
  if not (ui_sync_ports.is_popup_active and ui_sync_ports.is_popup_active(state)) then
    return false
  end
  if not _is_computer_popup_owner(game, state) then
    return false
  end
  local elapsed = runtime_state.get_modal_elapsed(state)
  return elapsed < min_popup_visible
end

local function _fill_auto_action_actor(auto_action, current_player_id)
  if auto_action and auto_action.type == "ui_button" and not auto_action.actor_role_id then
    auto_action.actor_role_id = current_player_id
  end
end

local function _log_missing_auto_choice_action(state, ctx)
  if not (ctx.pending_choice and ctx.current_player_computer_controlled == true) then
    return
  end
  if state.auto_runner.waiting_for_interval == true then
    return
  end
  runtime_state.log_once(
    state,
    "warn",
    "auto_runner_choice_no_action_" .. tostring(ctx.pending_choice.id),
    "[Eggy]",
    "auto runner produced no action for runtime pending choice",
    "choice_id=" .. tostring(ctx.pending_choice.id),
    "kind=" .. tostring(ctx.pending_choice.kind),
    "actor_role_id=" .. tostring(ctx.current_player_id)
  )
end
local function _initialize_ports(state, game)
  local ports = _resolve_ports(state)
  state.game = game
  game.state = game.state or {}
  state.gameplay_loop_ports = ports
  game.board_scene_port = gameplay_loop_runtime.build_board_scene_port(state)
  game.popup_port = gameplay_loop_runtime.build_popup_port(state)
  game.tip_output_port = gameplay_loop_runtime.build_tip_output_port(state)
  game.event_feed_port = event_feed_adapter.new(game, function()
    return ports.debug.sync_event_log(state)
  end)
  game.board_visual_feedback_port = gameplay_loop_runtime.build_board_visual_feedback_port(state)
  game.tile_feedback_port = gameplay_loop_runtime.build_tile_feedback_port(state)
  game.bankruptcy_feedback_port = {
    on_tiles_cleared = function(arg1, arg2, arg3, arg4)
      local game_ctx
      local owned_tile_ids
      if arg4 ~= nil then
        game_ctx = arg2
        owned_tile_ids = arg4
      else
        game_ctx = arg1
        owned_tile_ids = arg3
      end
      return game.board_visual_feedback_port.sync_many(game_ctx, {
        tile_ids = owned_tile_ids,
      })
    end,
  }
  game.anim_gate_port = gameplay_loop_runtime.build_anim_gate_port(state)
  game.intent_output_port = intent_dispatcher.build_port()
  _ensure_fallback_ports(game)
  return ports
end
local function _configure_tile_owner_notifier(game)
  game.tile_owner_notifier = {
    notify_owner_changed = function(_, tile_id)
      return game.board_visual_feedback_port.sync_many(game, {
        tile_ids = { tile_id },
      })
    end,
  }
end
local function _configure_environment(state, game, ports)
  local anim_ports = ports.anim
  local state_ports = ports.state
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  state_ports.apply_role_control_lock(state, false)
  turn_runtime.role_control_lock_active = false
  turn_runtime.role_control_lock_suppress = 0
  anim_ports.reset_status_3d(state)
  _configure_tile_owner_notifier(game)
  paid_currency_bridge.setup_for_game(game)
  market_purchase.setup_for_game(game)
  state_ports.install_event_handlers(game, logger, state)
  logger.set_info_per_turn_limit(debug_flags.info_log_per_turn_limit)
  logger.set_info_turn_provider(function() return game.turn and game.turn.turn_count end)
end
local function _configure_pending_choice(state, game, ports)
  local output_ports = ports.output
  local ui_sync_ports = ports.ui_sync
  local modal_ports = ports.modal
  assert(game.pending_choice ~= nil, "missing game.pending_choice")
  player_control_snapshot.install(game)
  local pending = game:pending_choice()
  output_ports.sync_pending_choice(state, pending)
  if pending then
    local model = ui_sync_ports.build_model(state, game)
    output_ports.sync_ui_model(state, model)
    if model.choice then
      modal_ports.open_choice_modal(state, model.choice, model.market)
    end
  end
end
local function _cancel_wait_deadlines(state)
  deadlines.cancel(state, "choice")
  deadlines.cancel(state, "market_buy")
  deadlines.cancel(state, "target_select")
  deadlines.cancel(state, "modal_popup")
end

local function _reset_runtime_state(state, ports)
  local ui_sync_ports = ports.ui_sync
  afk_signal.reset(state)
  _cancel_wait_deadlines(state)
  state._target_select_deadline_choice_id = nil
  state._target_select_timeout_choice_id = nil
  state.action_button_active = false
  state.action_button_elapsed = 0
  state.action_button_player_id = nil
  state.player_units = nil
  state.player_units_missing = false
  ports.output.invalidate_ui_model(state)
  state.countdown_last = nil
  state.countdown_active_last = nil
  if ui_sync_ports.set_input_blocked then
    ui_sync_ports.set_input_blocked(state, false)
  end
  if state.auto_runner then
    state.auto_runner:set_enabled(true)
    state.auto_runner:reset_timer()
  end
end

local function _find_player(game, role_id)
  if not game then
    return nil
  end
  if type(game.find_player_by_id) ~= "function" then
    return nil
  end
  return game:find_player_by_id(role_id)
end

local function _is_afk_player(player)
  return player_control.is_afk_delegated(player)
end

local function _resolve_afk_player(game, role_id)
  local player = _find_player(game, role_id)
  if _is_afk_player(player) then
    return player
  end
  return nil
end

local function _show_afk_recovery_hint(game, role_id)
  local player = _resolve_afk_player(game, role_id)
  local port = game.tip_output_port
  if not (player and port and type(port.enqueue) == "function") then
    return
  end
  port.enqueue(game, {
    text = "你正在托管中，点击托管按钮恢复",
    duration = timing.event_tip_default_seconds,
    role_id = player.id,
    blocks_inter_turn = false,
    source = "afk.auto_runner",
  })
end
function gameplay_loop.set_game(state, game)
  assert(game ~= nil, "missing game")
  runtime_state.ensure_all(state)
  landing_visual_hold.reset_state(state)
  wait_callbacks.reset_runtime(game)
  game.landing_visual_hold_state = state
  local ports = _initialize_ports(state, game)
  _configure_environment(state, game, ports)
  _configure_pending_choice(state, game, ports)
  _reset_runtime_state(state, ports)
end
function gameplay_loop.new_game(state)
  assert(state.game_factory, "game_factory not set")
  local game = state.game_factory()
  _build_item_index(state)
  local auto_runner = assert(state.auto_runner, "missing auto_runner")
  assert(auto_runner.reset_timer ~= nil, "missing auto_runner.ResetTimer")
  if auto_runner.set_enabled then
    auto_runner:set_enabled(true)
  end
  auto_runner:reset_timer()
  logger.info("启动蛋仔大富翁，玩家数:", #game.players)
  return game
end

-- auto runner 保持沉默的两种情形：输入被封锁，或 popup 还没散。
local function _is_auto_runner_blocked(game, state, ui_sync_ports)
  if ui_sync_ports.is_input_blocked and ui_sync_ports.is_input_blocked(state) then
    return true
  end
  return _is_computer_popup_waiting(game, state, ui_sync_ports)
end

function gameplay_loop.step_auto_runner(game, state, dt, context)
  assert(game ~= nil, "missing game")
  assert(state.auto_runner ~= nil, "missing auto_runner")
  local ports = _resolve_ports(state)
  local ui_sync_ports = ports.ui_sync
  if _is_auto_runner_blocked(game, state, ui_sync_ports) then
    return nil
  end
  local ctx = auto_context.build(game, context)
  local auto_action = state.auto_runner:next_action(dt, ctx)
  _fill_auto_action_actor(auto_action, ctx.current_player_id)
  if auto_action == nil then
    _log_missing_auto_choice_action(state, ctx)
  else
    _show_afk_recovery_hint(game, auto_action.actor_role_id or ctx.current_player_id)
    _dispatch_action_with_close_choice(game, state, auto_action, ports)
  end
  return auto_action
end
local _tick_deps = {
  step_auto_runner = nil,
  dispatch_action_with_close_choice = _dispatch_action_with_close_choice,
}
function gameplay_loop.tick(game, state, dt)
  if not game then
    return
  end
  _ensure_runtime_ports(game)
  local ports = _resolve_ports(state)
  if not state then
    return
  end
  afk_signal.prune(game, state)
  _tick_deps.step_auto_runner = gameplay_loop.step_auto_runner
  _tick_flow(game, state, dt, ports, _tick_deps)
  if game.finished and state then
    afk_signal.reset(state)
    _cancel_wait_deadlines(state)
  else
    afk_signal.prune(game, state)
  end
end
-- 行为测试接缝：场景与 test_auto_runner_policies 观察缺失自动动作的告警节流。
gameplay_loop._log_missing_auto_choice_action = _log_missing_auto_choice_action
-- 行为测试接缝：test_loop_fallback_ports 观察已有注入端口保留和缺失能力补齐。
gameplay_loop._M_test = {
  ensure_fallback_ports = _ensure_fallback_ports,
}
return gameplay_loop

