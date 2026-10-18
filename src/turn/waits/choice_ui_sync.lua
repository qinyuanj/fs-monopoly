local runtime_state = require("src.state.runtime")

local choice_ui_sync = {}

function choice_ui_sync.sync_pending_choice_ui(game, state, opts, output_ports)
  local pending = game.turn.pending_choice
  local active_choice = output_ports.get_pending_choice(state)
  if pending and (not active_choice or active_choice.id ~= pending.id) then
    output_ports.sync_pending_choice(state, pending)
    opts.on_pending_choice(game, state, pending)
  elseif not pending then
    output_ports.clear_pending_choice(state)
  end
  return pending, output_ports.get_pending_choice(state)
end

local function _resolve_choice_ui_gate(state, game, opts, active, active_choice)
  if active and active_choice and type(opts.resolve_choice_ui_state) == "function" then
    return opts.resolve_choice_ui_state(game, state, active_choice)
  end
  return nil
end

function choice_ui_sync.resolve_missing_ui_warning(state, game, opts, pending, active_choice, ui_choice_active)
  local active = pending ~= nil or active_choice ~= nil
  local resolved_ui_gate = _resolve_choice_ui_gate(state, game, opts, active, active_choice)
  local should_warn_missing_ui = active and active_choice and not ui_choice_active
  if type(resolved_ui_gate) == "table" then
    should_warn_missing_ui = resolved_ui_gate.should_warn == true
  end
  return active, should_warn_missing_ui, resolved_ui_gate
end

local _empty_gate = {}

local function _resolve_phase(game)
  local turn = game and game.turn
  local phase = turn and turn.phase
  return phase
end

-- #523 取证字段（部署目录验证后回收进仓库）：warn 带 gate 判定全字段，
-- 缺屏原因（席位/托管/phase/开屏哪一环）一条日志即可定位。
function choice_ui_sync.maybe_warn_missing_ui(state, game, active_choice, should_warn_missing_ui, resolved_ui_gate)
  if not should_warn_missing_ui then
    return
  end
  local gate = resolved_ui_gate or _empty_gate
  local phase = _resolve_phase(game)
  runtime_state.log_once(
    state,
    "warn",
    "choice_runtime_without_ui_" .. tostring(active_choice.id),
    "[Eggy]",
    "runtime pending choice active without ui.choice_active",
    "choice_id=" .. tostring(active_choice.id),
    "kind=" .. tostring(active_choice.kind),
    "owner_role_id=" .. tostring(active_choice.owner_role_id),
    "route_key=" .. tostring(gate.route_key or active_choice.route_key),
    "phase=" .. tostring(phase),
    "served_owner=" .. tostring(gate.served_owner),
    "owner_computer_controlled=" .. tostring(gate.owner_computer_controlled),
    "expects_ui=" .. tostring(gate.expects_ui),
    "open=" .. tostring(gate.open)
  )
end

-- #523 缺屏探针（帧内时序裁定见 #524）：只在 dirty 刷新之后被调用，open
-- 反映同帧补偿开屏后的真实状态；阻塞期创建、放行帧首开的窗口不再误报。
function choice_ui_sync.probe_missing_ui(game, state, opts, output_ports)
  local active_choice = output_ports.get_pending_choice(state)
  if active_choice == nil then
    return
  end
  local ui_choice_active = opts.is_choice_active(state) == true
  local _, should_warn_missing_ui, resolved_ui_gate = choice_ui_sync.resolve_missing_ui_warning(
    state, game, opts, nil, active_choice, ui_choice_active
  )
  choice_ui_sync.maybe_warn_missing_ui(state, game, active_choice, should_warn_missing_ui, resolved_ui_gate)
end

return choice_ui_sync

