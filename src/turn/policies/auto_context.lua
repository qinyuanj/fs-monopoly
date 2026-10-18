local runtime_state = require("src.state.runtime")
local control = require("src.player.control")
local ui_gate = require("src.turn.policies.ui_gate")
local tables = require("src.foundation.tables")

local auto_context = {}

local function _resolve_current_player_index(game, ctx)
  if ctx.current_player_index then
    return ctx.current_player_index
  end
  return game.turn and game.turn.current_player_index or nil
end

local function _is_computer_controlled(player)
  return player and control.is_computer_controlled(player) or false
end

local function _player_at(game, index)
  return index and game.players and game.players[index] or nil
end

local function _player_id(player)
  return player and player.id or nil
end

function auto_context.build(game, context)
  local ctx = context or {}
  ctx.game_finished = game.finished

  local current_player_index = _resolve_current_player_index(game, ctx)
  ctx.current_player_index = current_player_index

  local player = _player_at(game, current_player_index)
  if ctx.current_player_id == nil then
    ctx.current_player_id = _player_id(player)
  end
  if ctx.current_player_computer_controlled == nil then
    ctx.current_player_computer_controlled = _is_computer_controlled(player)
  end
  return ctx
end

local function _resolve_pending_choice(game, state)
  return game and game.turn and game.turn.pending_choice or runtime_state.get_pending_choice(state)
end

local function _ensure_tick_context(state)
  return tables.ensure_absent_field(state, "_tick_context")
end

local function _gate_flag(gate, key)
  return gate and gate[key] == true or false
end

local function _gate_modal_active(gate)
  return gate and (gate.popup_active == true or gate.market_active == true or gate.choice_active == true) or false
end

local function _apply_gate_flags(ctx, gate)
  ctx.choice_active = _gate_flag(gate, "choice_active")
  ctx.market_active = _gate_flag(gate, "market_active")
  ctx.popup_active = _gate_flag(gate, "popup_active")
  ctx.modal_active = _gate_modal_active(gate)
end

function auto_context.build_tick(game, state, ui_sync_ports)
  local gate = ui_gate.resolve(state, ui_sync_ports)
  local pending_choice = _resolve_pending_choice(game, state)
  local ctx = _ensure_tick_context(state)
  ctx.game = game
  ctx.state = state
  ctx.pending_choice = pending_choice
  ctx.current_player_index = nil
  ctx.current_player_id = nil
  ctx.current_player_computer_controlled = nil
  _apply_gate_flags(ctx, gate)
  ctx.modal_buttons = nil
  return auto_context.build(game, ctx)
end

return auto_context

