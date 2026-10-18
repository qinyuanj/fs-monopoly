local validator = require("src.turn.actions.validator")
local runtime_state = require("src.state.runtime")
local optional_action_completion = require("src.turn.optional_action_completion")
local ctx_mod = require("src.turn.actions.context")
local defaults = require("src.turn.actions.defaults")
local item_slot_click = require("src.turn.actions.item_slot_click")
local helpers = require("src.turn.actions.action_dispatcher_helpers")
local share_panel = require("src.foundation.ports.share_panel")
local control = require("src.player.control")

local handlers = {}

-- ui_button：auto 开关

-- 首次开启托管弹宿主分享面板。shown 标记只在宿主调用成功之后锁存：role 解析不出、
-- 宿主 Role 缺 show_map_share_panel、或宿主调用抛错时本次不弹但也不锁存，
-- 下次开启托管可重试（失败路径一律 warn，不静默吞）。宿主调用机制收敛在
-- share_panel.try_show（与分享按钮共用），日志前缀沿用历史钉住的 "auto share panel"。
local function _try_show_share_panel(actor_role_id, player)
  -- actor_role_id 恒可解析:唯一调用方 handle_auto_toggle 先经
  -- ctx_mod.resolve_actor_player 把 normalize 不出 role_id 的 action 挡成
  -- rejected。曾经的「unresolvable」分支不可达——等价变异体,按 #257 删冗余。
  if share_panel.try_show(actor_role_id, "auto share panel") then
    player.auto_share_panel_shown = true
  end
end

function handlers.handle_auto_toggle(game, action)
  local player = ctx_mod.resolve_actor_player(game, action)
  if not player then
    return { status = "rejected" }
  end
  local result = control.toggle_manual_delegation(player)
  -- 分享绑定「变为开启」：关闭方向的点击（含初始已托管的 roster/debug 对局）
  -- 与未变化的补位电脑命令不弹分享面板。
  if result.enabled and player.auto_share_panel_shown ~= true then
    _try_show_share_panel(action.actor_role_id, player)
  end
  return { status = "applied" }
end

-- ui_button：next 行动按钮冷却锁

local function _phase_lock_released(turn_runtime, phase)
  if turn_runtime.next_turn_lock_phase and phase and phase ~= turn_runtime.next_turn_lock_phase then
    return true
  end
  return turn_runtime.next_turn_last_click == nil
end

local function _lock_released(turn_runtime, phase)
  if not turn_runtime.next_turn_locked then
    return true
  end
  return _phase_lock_released(turn_runtime, phase)
end

function handlers.allow_next_turn(turn_runtime, phase, now, ctx)
  if _lock_released(turn_runtime, phase) then
    return true
  end
  local diff = ctx_mod.resolve_timestamp_diff_seconds(ctx, now, turn_runtime.next_turn_last_click)
  return diff and diff >= defaults.next_turn_cooldown
end

function handlers.handle_next_turn(step_turn_fn, game, state, action, ctx)
  local turn_runtime = runtime_state.ensure_turn_runtime(state)
  local phase = game.turn.phase
  local now = ctx_mod.resolve_timestamp_now(ctx)
  if not handlers.allow_next_turn(turn_runtime, phase, now, ctx) then
    return { status = "rejected" }
  end
  turn_runtime.next_turn_locked = true
  turn_runtime.next_turn_last_click = now
  turn_runtime.next_turn_lock_phase = phase
  if phase == "wait_action" then
    game:dispatch_action(action)
  else
    step_turn_fn(game)
  end
  return { status = "applied" }
end

-- ui_button：cancel 转发为 choice_cancel

function handlers.handle_cancel(dispatch_fn, game, state, action, opts, ctx)
  local choice = ctx_mod.resolve_pending_choice(game, state, ctx)
  if choice == nil or choice.allow_cancel == false then
    return { status = "rejected" }
  end
  return dispatch_fn(game, state, {
    type = "choice_cancel",
    choice_id = choice.id,
    actor_role_id = action.actor_role_id,
    input_source = action.input_source,
  }, opts, ctx)
end

-- ui_button：next 行动按钮

function handlers.handle_next(game, state, action, opts, ctx, step_turn_fn)
  if not validator.validate_actor_role(game, action) then
    return { status = "rejected" }
  end
  if action.id ~= "next" then
    return { status = "rejected" }
  end
  return handlers.handle_next_turn(step_turn_fn, game, state, action, ctx)
end

function handlers.handle_ui_button(dispatch_fn, step_turn_fn, game, state, action, opts, ctx)
  if action.id == "auto" then
    return handlers.handle_auto_toggle(game, action)
  end
  if action.id == "cancel" then
    return handlers.handle_cancel(dispatch_fn, game, state, action, opts, ctx)
  end
  return handlers.handle_next(game, state, action, opts, ctx, step_turn_fn)
end

-- item_slot_click：裁定独占在 item_slot_click，本处只按结论走。

function handlers.handle_item_slot_click(dispatch_fn, game, state, action, opts, ctx)
  local resolution = item_slot_click.resolve(game, action)
  if resolution.status ~= "select" then
    return { status = "rejected" }
  end
  return dispatch_fn(game, state, resolution.action, opts, ctx)
end

-- choice_select / choice_cancel

function handlers.handle_choice_action(game, state, action, opts, ctx, turn_dispatch)
  local choice = ctx_mod.resolve_pending_choice(game, state, ctx)
  if not validator.validate(action, { game = game, choice = choice }) then
    return { status = "rejected" }
  end
  if game then
    assert(game.dispatch_action ~= nil, "missing game.dispatch_action")
    game:dispatch_action(action)
  end
  helpers.clear_choice_if_closed(turn_dispatch, game, state, opts, choice)
  return { status = "applied" }
end

-- complete_optional_action_phase

function handlers.handle_optional_action_completion(dispatch_fn, game, state, action, opts, ctx)
  local gate_state = validator.resolve_gate_state(state, ctx.ui_sync_ports)
  local result = optional_action_completion.complete_optional_action_phase(game, action.actor_role_id, state, {
    gate_state = gate_state,
    input_source = action.input_source,
    dispatch_choice_action = function(choice_action)
      return dispatch_fn(game, state, choice_action, opts, ctx)
    end,
  })
  return helpers.optional_completion_status(result)
end

return handlers

