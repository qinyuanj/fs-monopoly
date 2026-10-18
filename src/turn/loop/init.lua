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

--[[ mutate4lua-manifest
version=4
projectHash=5a5363db18ceee1b
scope.0.id=chunk:src/turn/loop/init.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=543
scope.0.semanticHash=9e641fed09637603
scope.1.id=function:_noop
scope.1.kind=function
scope.1.startLine=30
scope.1.endLine=32
scope.1.semanticHash=d654da5e94a5e3f3
scope.2.id=function:<anonymous>
scope.2.kind=function
scope.2.startLine=34
scope.2.endLine=36
scope.2.semanticHash=67a06b9f43804ce2
scope.3.id=function:_fill_defaults
scope.3.kind=function
scope.3.startLine=51
scope.3.endLine=57
scope.3.semanticHash=adc7db31ed19f482
scope.4.id=function:_ensure_fallback_ports
scope.4.kind=function
scope.4.startLine=59
scope.4.endLine=68
scope.4.semanticHash=a8d99b8ecc3a3467
scope.5.id=function:_ensure_runtime_ports
scope.5.kind=function
scope.5.startLine=70
scope.5.endLine=78
scope.5.semanticHash=3d250ee336d75803
scope.6.id=function:_has_input_lock_methods
scope.6.kind=function
scope.6.startLine=80
scope.6.endLine=82
scope.6.semanticHash=c34090ddef7f018a
scope.7.id=function:_should_apply_input_lock
scope.7.kind=function
scope.7.startLine=84
scope.7.endLine=86
scope.7.semanticHash=a3ea65fcaba3b943
scope.8.id=function:_sync_input_lock
scope.8.kind=function
scope.8.startLine=88
scope.8.endLine=94
scope.8.semanticHash=8694453dca6c1012
scope.9.id=function:_ensure_anim_callbacks
scope.9.kind=function
scope.9.startLine=99
scope.9.endLine=104
scope.9.semanticHash=c9e7cceb4b68f6e7
scope.10.id=function:_move_anim_call_opts.on_move_anim
scope.10.kind=function
scope.10.startLine=102
scope.10.endLine=102
scope.10.semanticHash=aba9250a8c6b104f
scope.11.id=function:_action_anim_call_opts.on_action_anim
scope.11.kind=function
scope.11.startLine=103
scope.11.endLine=103
scope.11.semanticHash=aba9250a8c6b104f
scope.12.id=function:_step_phase_animation
scope.12.kind=function
scope.12.startLine=106
scope.12.endLine=117
scope.12.semanticHash=5e8c75a2d64100b5
scope.13.id=function:_accumulate_game_time
scope.13.kind=function
scope.13.startLine=119
scope.13.endLine=121
scope.13.semanticHash=5eb0b77d28a474a8
scope.14.id=function:_check_game_time_victory
scope.14.kind=function
scope.14.startLine=123
scope.14.endLine=127
scope.14.semanticHash=55f355dc09f894db
scope.15.id=function:_step_game_clock
scope.15.kind=function
scope.15.startLine=129
scope.15.endLine=133
scope.15.semanticHash=16141b90c32ccae1
scope.16.id=function:_step_tick_timeouts
scope.16.kind=function
scope.16.startLine=135
scope.16.endLine=155
scope.16.semanticHash=61cb9eb7cbc34ab6
scope.17.id=function:timer_ctx.dispatch_next
scope.17.kind=function
scope.17.startLine=146
scope.17.endLine=150
scope.17.semanticHash=6606ea606d9676cf
scope.18.id=function:_sync_tick_phase
scope.18.kind=function
scope.18.startLine=157
scope.18.endLine=163
scope.18.semanticHash=7c5e59b4ba750f73
scope.19.id=function:_refresh_tick_from_dirty
scope.19.kind=function
scope.19.startLine=165
scope.19.endLine=177
scope.19.semanticHash=51a548adb165f421
scope.20.id=function:_try_release_landing_visual
scope.20.kind=function
scope.20.startLine=179
scope.20.endLine=184
scope.20.semanticHash=c8066628834b6758
scope.21.id=function:_landing_visual_ready
scope.21.kind=function
scope.21.startLine=186
scope.21.endLine=190
scope.21.semanticHash=0d2c512620ff4791
scope.22.id=function:_maybe_advance_landing_visual
scope.22.kind=function
scope.22.startLine=192
scope.22.endLine=196
scope.22.semanticHash=55f355dc09f894db
scope.23.id=function:_tick_flow
scope.23.kind=function
scope.23.startLine=198
scope.23.endLine=214
scope.23.semanticHash=8c58bd16465e8366
scope.24.id=function:_resolve_ports
scope.24.kind=function
scope.24.startLine=216
scope.24.endLine=229
scope.24.semanticHash=92a19cb697e90233
scope.25.id=function:_dispatch_action_with_close_choice
scope.25.kind=function
scope.25.startLine=232
scope.25.endLine=241
scope.25.semanticHash=c0c2811d9f322c61
scope.26.id=function:_dispatch_opts.on_close_choice
scope.26.kind=function
scope.26.startLine=236
scope.26.endLine=238
scope.26.semanticHash=c772a22f8680e278
scope.27.id=function:_build_item_index
scope.27.kind=function
scope.27.startLine=242
scope.27.endLine=250
scope.27.semanticHash=5947813d80912d78
scope.28.id=function:_popup_owner_supported
scope.28.kind=function
scope.28.startLine=251
scope.28.endLine=253
scope.28.semanticHash=1c9b9cd6c331f2c3
scope.29.id=function:_popup_owner_index
scope.29.kind=function
scope.29.startLine=255
scope.29.endLine=260
scope.29.semanticHash=7e1e522c2499dc2a
scope.30.id=function:_computer_popup_actor
scope.30.kind=function
scope.30.startLine=262
scope.30.endLine=268
scope.30.semanticHash=d011e1dbb5c3c5ed
scope.31.id=function:_is_computer_popup_owner
scope.31.kind=function
scope.31.startLine=270
scope.31.endLine=278
scope.31.semanticHash=062d43793d983e0f
scope.32.id=function:_min_popup_visible_seconds
scope.32.kind=function
scope.32.startLine=280
scope.32.endLine=282
scope.32.semanticHash=30522eb92944bea7
scope.33.id=function:_is_computer_popup_waiting
scope.33.kind=function
scope.33.startLine=284
scope.33.endLine=297
scope.33.semanticHash=fa8e69ee69f19d64
scope.34.id=function:_fill_auto_action_actor
scope.34.kind=function
scope.34.startLine=299
scope.34.endLine=303
scope.34.semanticHash=d6c4cfd10774f95f
scope.35.id=function:_log_missing_auto_choice_action
scope.35.kind=function
scope.35.startLine=305
scope.35.endLine=322
scope.35.semanticHash=f9721a6675fd4b6a
scope.36.id=function:_initialize_ports
scope.36.kind=function
scope.36.startLine=323
scope.36.endLine=356
scope.36.semanticHash=9a149b5f20aceaaf
scope.37.id=function:<anonymous>#2
scope.37.kind=function
scope.37.startLine=331
scope.37.endLine=333
scope.37.semanticHash=7bbf31ab6751de78
scope.38.id=function:<anonymous>#3
scope.38.kind=function
scope.38.startLine=337
scope.38.endLine=350
scope.38.semanticHash=28bc2426dd56a83e
scope.39.id=function:_configure_tile_owner_notifier
scope.39.kind=function
scope.39.startLine=357
scope.39.endLine=365
scope.39.semanticHash=64064cdb551a24d1
scope.40.id=function:<anonymous>#4
scope.40.kind=function
scope.40.startLine=359
scope.40.endLine=363
scope.40.semanticHash=98267e765894f694
scope.41.id=function:_configure_environment
scope.41.kind=function
scope.41.startLine=366
scope.41.endLine=380
scope.41.semanticHash=87a49f62a9df52f6
scope.42.id=function:<anonymous>#5
scope.42.kind=function
scope.42.startLine=379
scope.42.endLine=379
scope.42.semanticHash=ce30d388318bb504
scope.43.id=function:_configure_pending_choice
scope.43.kind=function
scope.43.startLine=381
scope.43.endLine=396
scope.43.semanticHash=bf188db75eab4b0b
scope.44.id=function:_cancel_wait_deadlines
scope.44.kind=function
scope.44.startLine=397
scope.44.endLine=402
scope.44.semanticHash=6bb1e516eda8283b
scope.45.id=function:_reset_runtime_state
scope.45.kind=function
scope.45.startLine=404
scope.45.endLine=425
scope.45.semanticHash=00e00ea8f55b4e82
scope.46.id=function:_find_player
scope.46.kind=function
scope.46.startLine=427
scope.46.endLine=435
scope.46.semanticHash=06df476dc842a8cf
scope.47.id=function:_is_afk_player
scope.47.kind=function
scope.47.startLine=437
scope.47.endLine=439
scope.47.semanticHash=f1ce1850b7232305
scope.48.id=function:_resolve_afk_player
scope.48.kind=function
scope.48.startLine=441
scope.48.endLine=447
scope.48.semanticHash=a13878b4568f1608
scope.49.id=function:_show_afk_recovery_hint
scope.49.kind=function
scope.49.startLine=449
scope.49.endLine=462
scope.49.semanticHash=572c60d7520cf8ca
scope.50.id=function:gameplay_loop.set_game
scope.50.kind=function
scope.50.startLine=463
scope.50.endLine=473
scope.50.semanticHash=42c7be030a242c81
scope.51.id=function:gameplay_loop.new_game
scope.51.kind=function
scope.51.startLine=474
scope.51.endLine=486
scope.51.semanticHash=ea90d258ad4e850a
scope.52.id=function:_is_auto_runner_blocked
scope.52.kind=function
scope.52.startLine=489
scope.52.endLine=494
scope.52.semanticHash=cb9c219c06cdd575
scope.53.id=function:gameplay_loop.step_auto_runner
scope.53.kind=function
scope.53.startLine=496
scope.53.endLine=514
scope.53.semanticHash=c3fa719e89c8b5bc
scope.54.id=function:gameplay_loop.tick
scope.54.kind=function
scope.54.startLine=519
scope.54.endLine=537
scope.54.semanticHash=399a815464f1ffa1
]]
