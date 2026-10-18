local turn_action_gate = require("src.turn.policies.action_gate")
local ui_gate = require("src.turn.policies.ui_gate")

local validator_gate = {}

local function _extract_turn_state(state)
  if type(state) == "table" and state.game then
    return state.game.turn
  end
  return nil
end

local function _gate_flags(gate)
  return {
    input_blocked = gate.input_blocked == true,
    choice_active = gate.choice_active == true,
    market_active = gate.market_active == true,
    popup_active = gate.popup_active == true,
  }
end

local function _apply_turn_flags(flags, turn)
  flags.phase = turn and turn.phase or nil
  flags.detained_wait_active = turn and turn.detained_wait_active == true or false
  return flags
end

function validator_gate.resolve_gate_state(state, ui_sync_ports)
  local gate = turn_action_gate.resolve_gate_state(ui_gate.resolve(state, ui_sync_ports))
  return _apply_turn_flags(_gate_flags(gate), _extract_turn_state(state))
end

validator_gate.should_block_action = turn_action_gate.should_block_action

return validator_gate

