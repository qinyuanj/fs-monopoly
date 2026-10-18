-- 弹层超时步进与默认装配；超时策略由本模块与 ui_gate 共同提供。
local constants = require("src.config.content.constants")
local number_utils = require("src.foundation.number")
-- #329:端口组解析 accessor 归 turn.output(中立归属),waits 不再反向
-- require loop。
local resolve_port = require("src.turn.output.resolve_port")
local output_state_adapter = require("src.turn.output.state_adapter")
local tick_ui_gate = require("src.turn.waits.ui_gate")

local modal_timeout = {}

local function _modal_ports(state)
  return state and state.gameplay_loop_ports and state.gameplay_loop_ports.modal or nil
end

local function _has_close_method(modal_ports)
  return type(modal_ports.close_choice_modal) == "function" or type(modal_ports.close_popup) == "function"
end

function modal_timeout.resolve_modal_ports(state)
  local modal_ports = _modal_ports(state)
  if type(modal_ports) ~= "table" then
    return nil
  end
  return _has_close_method(modal_ports) and modal_ports or nil
end

local function _modal_timeout_override(opts, state)
  if not (opts and opts.get_timeout_seconds) then
    return nil
  end
  local override = opts.get_timeout_seconds(state)
  if override ~= nil and number_utils.is_numeric(override) then
    return override
  end
  return nil
end

local function _resolve_modal_timeout(opts, state)
  return _modal_timeout_override(opts, state) or constants.action_timeout_seconds or 0
end

local function _resolve_modal_output_ports(state)
  return resolve_port.resolve(state, "output", output_state_adapter)
end

local function _assert_modal_opts(opts)
  assert(opts ~= nil, "missing opts")
  assert(opts.is_active ~= nil, "missing opts.is_active")
  assert(opts.on_timeout ~= nil, "missing opts.on_timeout")
  assert(opts.get_ref ~= nil, "missing opts.get_ref")
end

-- 两张共享计时载荷表的字段在每次 sync_modal_timer 前恒被覆写,初值恒不可读
-- (等价变异体,按 #257 三分类删冗余)。
local _modal_timer_reset = {}
local _modal_timer_update = {}
local _modal_timer_empty = {}

local function _resolve_modal_ref(output_ports, state, opts)
  local ref = assert(opts.get_ref(state), "missing modal ref")
  if output_ports.get_modal_ref(state) ~= ref then
    _modal_timer_reset.ref = ref
    _modal_timer_reset.elapsed_seconds = 0
    output_ports.sync_modal_timer(state, _modal_timer_reset)
  end
  return ref
end

local function _update_modal_elapsed(output_ports, state, ref, dt)
  local next_elapsed = output_ports.get_modal_elapsed(state) + (dt or 0)
  _modal_timer_update.ref = ref
  _modal_timer_update.elapsed_seconds = next_elapsed
  output_ports.sync_modal_timer(state, _modal_timer_update)
  return next_elapsed
end

local function _handle_modal_timeout(output_ports, state, ref, on_timeout)
  _modal_timer_reset.ref = ref
  _modal_timer_reset.elapsed_seconds = 0
  output_ports.sync_modal_timer(state, _modal_timer_reset)
  on_timeout(state)
end

function modal_timeout.step(state, dt, opts)
  local output_ports = _resolve_modal_output_ports(state)
  local timeout = _resolve_modal_timeout(opts, state)
  if timeout <= 0 then
    output_ports.sync_modal_timer(state, _modal_timer_empty)
    return
  end
  _assert_modal_opts(opts)
  if not opts.is_active(state) then
    output_ports.sync_modal_timer(state, _modal_timer_empty)
    return
  end
  local ref = _resolve_modal_ref(output_ports, state, opts)
  local next_elapsed = _update_modal_elapsed(output_ports, state, ref, dt)
  if next_elapsed >= timeout then
    _handle_modal_timeout(output_ports, state, ref, opts.on_timeout)
  end
end

-- 默认弹层策略：
-- 超时时长走 ui_gate(宿主弹层可覆写),超时动作走 modal 端口收屏。
local _default_policy = {
  get_timeout_seconds = function(_, state)
    return tick_ui_gate.resolve_modal_timeout_seconds(state)
  end,
  on_timeout = function(ctx)
    local ports = modal_timeout.resolve_modal_ports(ctx)
    if ports and ports.close_popup then
      ports.close_popup(ctx)
      return
    end
  end,
}

local _default_opts = {
  _game = nil,
  on_timeout = _default_policy.on_timeout,
}

_default_opts.is_active = function(ctx)
  local gate = tick_ui_gate.resolve_ui_gate(ctx)
  return gate.popup_active == true
end

_default_opts.get_ref = function(ctx)
  local gate = tick_ui_gate.resolve_ui_gate(ctx)
  -- popup_active 恒 true(step 先过 is_active 闸门才调 get_ref);popup_seq 缺失
  -- 由 step 的 `assert(ref, "missing modal ref")` 兜底。
  return gate.popup_seq
end

_default_opts.get_timeout_seconds = function(state_ctx)
  return _default_policy.get_timeout_seconds(_default_opts._game, state_ctx)
end

-- 默认弹层超时步进：
-- game 只经 opts 透传给 get_timeout_seconds,步进结束即清,不留跨调用状态。
function modal_timeout.step_default(game, state, dt)
  _default_opts._game = game
  modal_timeout.step(state, dt, _default_opts)
  _default_opts._game = nil
end

return modal_timeout

