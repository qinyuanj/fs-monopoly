local ctx_mod = require("src.turn.actions.context")

local helpers = {}

local INVALIDATING_ACTION_TYPES = {
  ui_button = true,
  item_slot_click = true,
  choice_select = true,
  choice_cancel = true,
  complete_optional_action_phase = true,
  market_page_prev = true,
  market_page_next = true,
  market_tab_select = true,
}

function helpers.should_invalidate_ui(action)
  return INVALIDATING_ACTION_TYPES[action.type] == true
end

function helpers.invalidate_ui_model(output_ports, state)
  if output_ports and type(output_ports.invalidate_ui_model) == "function" then
    output_ports.invalidate_ui_model(state)
  end
end

local function _blocked_gate(gate_state)
  return gate_state ~= nil and gate_state.input_blocked == true
end

local function _cancel_action(action)
  return action ~= nil and action.type == "choice_cancel"
end

local function _market_buy_choice(choice)
  return choice ~= nil and choice.kind == "market_buy"
end

local function _same_choice(action, choice)
  return action.choice_id ~= nil and choice.id ~= nil and action.choice_id == choice.id
end

function helpers.allows_market_cancel_while_blocked(gate_state, game, state, action, ctx)
  if not _blocked_gate(gate_state) then
    return false
  end
  if not _cancel_action(action) then
    return false
  end
  local choice = ctx_mod.resolve_pending_choice(game, state, ctx)
  if not _market_buy_choice(choice) then
    return false
  end
  return _same_choice(action, choice)
end

local function _pending_choice(game)
  return game and game.turn and game.turn.pending_choice or nil
end

local function _choice_closed(pending, choice)
  return choice ~= nil and (pending == nil or pending.id == nil or pending.id ~= choice.id)
end

function helpers.clear_choice_if_closed(turn_dispatch, game, state, opts, choice)
  local pending = _pending_choice(game)
  if _choice_closed(pending, choice) then
    turn_dispatch.clear_choice(state, opts)
  end
end

function helpers.optional_completion_status(result)
  if result.ok == true then
    return { status = "applied" }
  end
  if result.reason == "blocked" then
    return { status = "blocked", reason = result.reason }
  end
  return { status = "rejected", reason = result.reason }
end

function helpers.ensure_input_source(action)
  if action.input_source == nil then
    action.input_source = "user"
  end
end

return helpers

