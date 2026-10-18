local logger = require("src.foundation.log")
local choice_ports = require("src.turn.deadlines.choice_ports")
local pending_confirmation = require("src.state.pending_confirmation")

local force_skip = {}

local function _should_refund_preconsume(choice)
  if type(choice) ~= "table" or type(choice.meta) ~= "table" then
    return false
  end
  if choice.meta.item_preconsumed ~= true then
    return false
  end
  return choice.meta.item_id ~= nil and choice.owner_role_id ~= nil
end

local function _game_or_state_game(game, state)
  return game or (state and state._game or nil)
end

local function _refund_helper()
  local ok, helper = pcall(require, "src.rules.choice.item_preconsume_policy")
  if ok and type(helper) == "table" and type(helper.refund) == "function" then
    return helper
  end
  return nil
end

local function _refund_preconsume(game, state, choice)
  if not _should_refund_preconsume(choice) then
    return
  end
  local helper = _refund_helper()
  if helper then
    pcall(helper.refund, _game_or_state_game(game, state), choice)
  end
end

local function _emitable(monopoly_events)
  return type(monopoly_events) == "table" and type(monopoly_events.emit) == "function"
end

local function _choice_field(choice, key)
  return choice and choice[key] or nil
end

local function _force_skip_payload(reason, choice)
  return {
    reason = reason or "tick_timeout",
    choice_id = _choice_field(choice, "id"),
    kind = _choice_field(choice, "kind"),
  }
end

local function _emit_foundation_event(reason, choice)
  local ok, monopoly_events = pcall(require, "src.foundation.events")
  if ok and _emitable(monopoly_events) then
    pcall(monopoly_events.emit, "fb.choice_force_skipped", _force_skip_payload(reason, choice))
  end
end

local function _log_force_skip_event(reason, choice)
  logger.warn("[Eggy]", "choice_force_skipped",
    "reason=" .. tostring(reason),
    "choice_id=" .. tostring(choice and choice.id or nil),
    "kind=" .. tostring(choice and choice.kind or nil))
end

local function _emit_force_skip_event(reason, choice)
  _emit_foundation_event(reason, choice)
  _log_force_skip_event(reason, choice)
end

local function _mark_force_skip_pending(game, state)
  if type(state) == "table" then
    state._choice_force_skip_pending = true
  end
  if game and game.turn then
    game.turn._choice_force_skip_pending = true
  end
end

local function _clear_pending_choice_via_port(state)
  local output_ports = choice_ports.resolve_output_ports(state)
  if output_ports then
    local clear_pending_choice = output_ports.clear_pending_choice
    if type(clear_pending_choice) == "function" then
      pcall(clear_pending_choice, state)
    end
  end
end

local function _clear_force_skip_state(game, state)
  if type(state) == "table" then
    pending_confirmation.clear(state, pending_confirmation.SOURCE_ITEM_PHASE_ASK)
    _clear_pending_choice_via_port(state)
  end
  if game and game.turn then
    game.turn.pending_choice = nil
  end
end

local function _cancel_choice_deadlines(api, state)
  if type(state) ~= "table" then
    return
  end
  api.cancel(state, "choice")
  api.cancel(state, "market_buy")
  api.cancel(state, "target_select")
  api.cancel(state, "modal_popup")
end

local function _advance_after_force_skip(game)
  if game and not game.finished and type(game.advance_turn) == "function" then
    pcall(game.advance_turn, game)
  end
end

function force_skip.install(api)
  function api.force_skip(game, state, choice, reason)
    _mark_force_skip_pending(game, state)
    _refund_preconsume(game, state, choice)
    _clear_force_skip_state(game, state)
    _cancel_choice_deadlines(api, state)
    _emit_force_skip_event(reason, choice)
    _advance_after_force_skip(game)
  end
end

return force_skip

