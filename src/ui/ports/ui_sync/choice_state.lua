local choice_route_policy = require("src.config.choice.route_policy")
local ui_gate_sync = require("src.ui.ports.ui_sync.gate")
local choice_owner = require("src.ui.ports.ui_sync.choice_owner")
local player_control_snapshot = require("src.turn.output.player_control_snapshot")
local input_lock = require("src.state.input_lock")

local choice_ui_state = {}

choice_ui_state.resolve_route_key = choice_route_policy.resolve

local _cached_gate_state = {}
local _open_state_gate = {}

local function _choice_screen_active(gate, ui, route_key)
  return gate.choice_active and ui ~= nil and ui.active_choice_screen_key == route_key or false
end

local function _resolve_choice_open_state(route_key, ui, game)
  if choice_route_policy.is_screenless_route(route_key) then
    return true
  end
  local gate = ui_gate_sync.snapshot(ui, _open_state_gate)
  if route_key == "market" then
    return gate.market_active
  end
  return _choice_screen_active(gate, ui, route_key)
end

-- 拥有者是否由电脑执行:消费 turn 输出侧物化的同一份玩家控制快照。
local function _owner_computer_controlled(game, owner_role_id)
  local entry = player_control_snapshot.find(game, owner_role_id)
  return entry ~= nil and entry.is_computer_controlled == true or false
end

-- 是否期待 UI 参与:非内联路由、非输入阻塞、owner 是本进程服务的席位且非电脑执行。
local function _expects_ui(route_key, game, served_owner, owner_computer_controlled)
  return route_key ~= "base_inline" and not input_lock.is_game_input_blocked(game) and served_owner and not owner_computer_controlled
end

local function _resolve_owner_state(game, choice, route_key)
  local owner_role_id = choice_owner.resolve_owner_role_id(game, choice)
  local served_owner = choice_owner.owner_is_served_seat(owner_role_id)
  local owner_computer_controlled = _owner_computer_controlled(game, owner_role_id)
  local expects_ui = _expects_ui(route_key, game, served_owner, owner_computer_controlled)
  return owner_role_id, served_owner, owner_computer_controlled, expects_ui
end

function choice_ui_state.resolve_gate_state(game, state, choice)
  local route_key = choice_ui_state.resolve_route_key(choice)
  local ui = state and state.ui or nil
  local owner_role_id, served_owner, owner_computer_controlled, expects_ui = _resolve_owner_state(game, choice, route_key)
  local open = _resolve_choice_open_state(route_key, ui, game)
  _cached_gate_state.route_key = route_key
  _cached_gate_state.owner_role_id = owner_role_id
  _cached_gate_state.served_owner = served_owner
  _cached_gate_state.owner_computer_controlled = owner_computer_controlled
  _cached_gate_state.expects_ui = expects_ui
  _cached_gate_state.open = open
  _cached_gate_state.should_warn = expects_ui and not open
  return _cached_gate_state
end

function choice_ui_state.should_reconcile(game, state, choice)
  local gate = choice_ui_state.resolve_gate_state(game, state, choice)
  return gate.expects_ui and not gate.open
end

return choice_ui_state

