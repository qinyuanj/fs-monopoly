-- #329:端口组解析 accessor 归 turn.output(中立归属),deadlines 不再反向
-- require loop。
local resolve_port = require("src.turn.output.resolve_port")
local owner = require("src.turn.choice.owner")

local choice_ports = {}

function choice_ports.resolve_modal_ports(state)
  local resolved = state and (state._resolved_gameplay_loop_ports or state.gameplay_loop_ports) or nil
  if type(resolved) ~= "table" then
    return nil
  end
  return resolved.modal
end

function choice_ports.resolve_output_ports(state)
  return resolve_port.resolve(state, "output", require("src.turn.output.state_adapter"))
end

function choice_ports.is_action_dispatchable(action)
  if type(action) ~= "table" then
    return false
  end
  return action.type == "choice_select"
    or action.type == "choice_cancel"
    or action.type == "complete_optional_action_phase"
end

function choice_ports.ensure_actor_role_id(game, choice, action)
  owner.ensure_actor_role_id(game, choice, action)
end

local function _dispatch_to_game(game, action)
  if game and type(game.dispatch_action) == "function" then
    pcall(game.dispatch_action, game, action)
  end
end

local function _clear_game_pending_choice(game, action)
  if game and game.turn then
    local pending = game.turn.pending_choice
    if not pending or pending.id ~= action.choice_id then
      game.turn.pending_choice = nil
    end
  end
end

local function _close_modal_choice(state)
  local modal_ports = choice_ports.resolve_modal_ports(state)
  if modal_ports and type(modal_ports.close_choice_modal) == "function" then
    pcall(modal_ports.close_choice_modal, state)
  end
end

local function _clear_output_choice(state)
  if type(state) == "table" then
    local output_ports = choice_ports.resolve_output_ports(state)
    if output_ports and type(output_ports.clear_pending_choice) == "function" then
      pcall(output_ports.clear_pending_choice, state)
    end
  end
end

function choice_ports.dispatch_via_close_choice(game, state, action)
  _dispatch_to_game(game, action)
  _clear_game_pending_choice(game, action)
  _close_modal_choice(state)
  _clear_output_choice(state)
end

return choice_ports

