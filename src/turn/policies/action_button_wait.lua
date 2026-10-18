local action_button_wait = {}

local function _choice_active(ui_sync_ports, state)
  return ui_sync_ports and ui_sync_ports.is_choice_active and ui_sync_ports.is_choice_active(state)
end

local function _popup_active(ui_sync_ports, state)
  return ui_sync_ports and ui_sync_ports.is_popup_active and ui_sync_ports.is_popup_active(state)
end

local function _has_blocking_ui(ui_sync_ports, state)
  return _choice_active(ui_sync_ports, state) or _popup_active(ui_sync_ports, state)
end

local function _is_ui_state_absent(ui_sync_ports, state)
  return ui_sync_ports
    and ui_sync_ports.get_ui_state
    and not ui_sync_ports.get_ui_state(state)
end

local function _is_input_blocked_port(ui_sync_ports, state)
  return ui_sync_ports
    and ui_sync_ports.is_input_blocked
    and ui_sync_ports.is_input_blocked(state)
end

local function _get_valid_ui_sync(game, state, ports)
  if not (game and state and ports) then
    return nil, false
  end
  return ports.ui_sync, true
end

local function _is_blocked_after_ui_ready(game, state, ui_sync_ports)
  if _is_input_blocked_port(ui_sync_ports, state) then
    return true
  end
  if _has_blocking_ui(ui_sync_ports, state) then
    return true
  end
  return game.turn ~= nil and game.turn.pending_choice ~= nil
end

function action_button_wait.is_action_button_wait_active(game, state, ports)
  local ui_sync_ports, is_valid = _get_valid_ui_sync(game, state, ports)
  if not is_valid then
    return false
  end
  if _is_ui_state_absent(ui_sync_ports, state) then
    return false
  end
  if game.finished then
    return false
  end
  return not _is_blocked_after_ui_ready(game, state, ui_sync_ports)
end

return action_button_wait

