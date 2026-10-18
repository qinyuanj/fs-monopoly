-- turn/actions 派发深模块：本文件只负责动作类型 → handler 映射与装配
-- （ui_button / item_slot_click / choice / market / force_skip / 可选行动收尾），
-- 子处理实现分居 action_dispatcher_handlers / action_dispatcher_helpers /
-- action_dispatcher_market；校验统一走 src.turn.actions.validator，
-- 道具槽点击的裁定独占在 src.turn.actions.item_slot_click。
local validator = require("src.turn.actions.validator")
local output_state_adapter = require("src.turn.output.state_adapter")
local ctx_mod = require("src.turn.actions.context")
local defaults = require("src.turn.actions.defaults")
local handlers = require("src.turn.actions.action_dispatcher_handlers")
local helpers = require("src.turn.actions.action_dispatcher_helpers")
local market = require("src.turn.actions.action_dispatcher_market")

local turn_dispatch = {}

local function _step_turn(game)
  assert(game ~= nil, "missing game")
  if game.finished then
    return
  end
  game:advance_turn()
end

local function _clear_choice(state, opts)
  local output_ports = defaults.resolve_port_group(state, "output") or output_state_adapter
  output_ports.clear_pending_choice(state)
  if opts and opts.on_close_choice then
    opts.on_close_choice(state)
  end
end

local function _build_default_handlers(dispatch_action, dispatcher)
  return {
    ui_button = function(game, state, action, opts, ctx)
      return handlers.handle_ui_button(dispatch_action, dispatcher.step_turn, game, state, action, opts, ctx)
    end,
    item_slot_click = function(game, state, action, opts, ctx)
      return handlers.handle_item_slot_click(dispatch_action, game, state, action, opts, ctx)
    end,
    choice_select = function(game, state, action, opts, ctx)
      return handlers.handle_choice_action(game, state, action, opts, ctx, dispatcher)
    end,
    choice_cancel = function(game, state, action, opts, ctx)
      return handlers.handle_choice_action(game, state, action, opts, ctx, dispatcher)
    end,
    complete_optional_action_phase = function(game, state, action, opts, ctx)
      return handlers.handle_optional_action_completion(dispatch_action, game, state, action, opts, ctx)
    end,
    market_page_prev = market.handle_market_navigation,
    market_page_next = market.handle_market_navigation,
    market_tab_select = market.handle_market_navigation,
    choice_force_skip = market.handle_force_skip,
  }
end

local function _dependency(deps, key, fallback)
  return deps[key] or fallback
end

function turn_dispatch.new(deps)
  deps = deps or {}
  local gate = _dependency(deps, "gate", validator)
  local context = _dependency(deps, "context", ctx_mod)
  local dispatcher = {
    step_turn = _dependency(deps, "step_turn", _step_turn),
    clear_choice = _dependency(deps, "clear_choice", _clear_choice),
  }
  local action_handlers
  local dispatch_action

  dispatch_action = function(game, state, action, opts, dispatch_ctx)
    assert(action ~= nil, "missing action")
    helpers.ensure_input_source(action)
    local ctx = context.resolve_dispatch_context(state, dispatch_ctx)
    local gate_state = gate.resolve_gate_state(state, ctx.ui_sync_ports)
    local blocked_by_gate = gate.should_block_action(gate_state, action)
    local allows_market_cancel = helpers.allows_market_cancel_while_blocked(gate_state, game, state, action, ctx)
    if blocked_by_gate and not allows_market_cancel then
      return { status = "blocked" }
    end
    if helpers.should_invalidate_ui(action) then
      helpers.invalidate_ui_model(ctx.output_ports, state)
    end
    local handler = action_handlers[action.type]
    if handler ~= nil then
      return handler(game, state, action, opts, ctx, dispatch_action)
    end
    return { status = "rejected" }
  end

  action_handlers = _dependency(deps, "handlers", _build_default_handlers(dispatch_action, dispatcher))

  function dispatcher.should_block_action(state, action_or_type)
    local dispatch_ctx = context.resolve_dispatch_context(state)
    local gate_state = gate.resolve_gate_state(state, dispatch_ctx.ui_sync_ports)
    return gate.should_block_action(gate_state, action_or_type)
  end

  function dispatcher.dispatch_action(game, state, action, opts)
    return dispatch_action(game, state, action, opts, nil)
  end

  return dispatcher
end

turn_dispatch.step_turn = _step_turn
turn_dispatch.clear_choice = _clear_choice

local default_dispatcher = turn_dispatch.new({
  step_turn = function(game)
    return turn_dispatch.step_turn(game)
  end,
  clear_choice = function(state, opts)
    return turn_dispatch.clear_choice(state, opts)
  end,
})

turn_dispatch.should_block_action = default_dispatcher.should_block_action
turn_dispatch.dispatch_action = default_dispatcher.dispatch_action

return turn_dispatch

