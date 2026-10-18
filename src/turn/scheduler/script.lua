-- 回合脚本协程 runner：wait 处理器表、phase 执行与 yield/finish 状态机。
-- 信号泵与 session 构造均由 src.turn.scheduler.runtime 私有协调。
local turn_decision = require("src.turn.waits.decision")
local default_await_handlers = require("src.turn.scheduler.await")
local move_followup = require("src.turn.phases.move_followup")

local M = {}

---@param await_handlers TurnAwaitHandlers?
---@return TurnAwaitHandlers
local function _wait_handlers(await_handlers)
  local await = await_handlers or default_await_handlers
  return {
    wait_action = await.action,
    wait_choice = await.choice,
    wait_move_anim = await.move_anim,
    wait_action_anim = await.action_anim,
    wait_landing_visual = await.landing_visual,
    detained_wait = await.detained,
    inter_turn_wait = await.inter_turn,
    wait_seconds = function(session, args)
      return await.seconds(session, args and args.seconds, args)
    end,
  }
end

local function _resolve_phase_handler(phases, state_name)
  local handler = phases[state_name]
  if handler ~= nil or state_name ~= "move_followup" then
    return handler
  end
  return move_followup.run
end

local function _call_metamethod(value)
  local metatable = type(value) == "table" and getmetatable(value) or nil
  return metatable and metatable.__call or nil
end

local function _is_callable(value)
  return type(value) == "function" or type(_call_metamethod(value)) == "function"
end

local function _run_phase(session, state_name, args)
  local phases = session.phases
  assert(type(phases) == "table", "missing session phases")
  local handler = _resolve_phase_handler(phases, state_name)
  assert(_is_callable(handler), "missing phase handler: " .. tostring(state_name))
  if state_name == "start" then
    turn_decision.log_turn_start(session.game)
  end
  session:mark_phase(state_name)
  local turn_mgr = session.turn_mgr or session
  ---@cast handler function
  return handler(turn_mgr, args)
end

local function _run_wait(session, state_name, args, await_handlers)
  local handler = _wait_handlers(await_handlers)[state_name]
  if handler == nil then
    return nil
  end
  return handler(session, args)
end

local function _set_current_state(session, state_name, state_args)
  session.current_state = state_name
  session.current_args = state_args
end

local _yield_payload = { kind = "wait", wait_state = nil }

local function _yield_wait(session, state_name)
  session.wait_state = state_name
  _yield_payload.wait_state = state_name
  coroutine.yield(_yield_payload)
end

local function _step_script(session, state_name, state_args, await_handlers)
  _set_current_state(session, state_name, state_args)
  local wait_res = _run_wait(session, state_name, state_args, await_handlers)
  if wait_res == nil then
    return _run_phase(session, state_name, state_args)
  end
  if wait_res.wait then
    _yield_wait(session, state_name)
    return state_name, state_args
  end
  return wait_res.next_state, wait_res.next_args
end

local function _finish_script(session)
  session.current_state = nil
  session.current_args = nil
  session.wait_state = nil
  session.finished = true
end

local function _initial_state(session)
  return session.current_state or "start"
end

---@param session table
---@param await_handlers TurnAwaitHandlers?
---@return thread
function M.create(session, await_handlers)
  assert(session ~= nil, "missing script session")
  return coroutine.create(function()
    local state_name = _initial_state(session)
    local state_args = session.current_args
    while state_name do
      state_name, state_args = _step_script(session, state_name, state_args, await_handlers)
    end
    _finish_script(session)
  end)
end

return M

