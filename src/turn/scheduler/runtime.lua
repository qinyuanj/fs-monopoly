local timing_session = require("src.turn.scheduler.session")
local timing_script = require("src.turn.scheduler.script")
local dirty_tracker = require("src.state.dirty_tracker")
local choice_lifecycle = require("src.turn.choice.lifecycle")
local Class = require("src.foundation.class")

---@class TurnScheduler : Class
---@field private game table
---@field private phases table
---@field private await_handlers table?
---@field private _turn_mgr table
---@field private _session table
local scheduler = Class("TurnScheduler")

local SIGNAL_ACTION = "action"
local SIGNAL_TICK = "tick"

local function _emit_turn_prompt(turn, player_id)
  if not (turn and player_id) then return end
  turn.turn_start_prompt_seq = (turn.turn_start_prompt_seq or 0) + 1
  turn.turn_start_prompt_player_id = player_id
end

local function _next_player(runtime)
  local game = runtime.game
  choice_lifecycle.assert_cleared_on_turn_advance(game)
  local next_index = game.turn.current_player_index % #game.players + 1
  game.turn.current_player_index = next_index
  local next_player = game.players[next_index]
  _emit_turn_prompt(game.turn, next_player and next_player.id)
  dirty_tracker.mark_turn(game)
end

local function _build_turn_mgr(runtime)
  return {
    game = runtime.game,
    phases = runtime.phases,
    next_player = function()
      return _next_player(runtime)
    end,
  }
end

function scheduler:init(game, phases, await_handlers)
  assert(game ~= nil, "missing game")
  assert(phases ~= nil, "missing phases")
  self.game = game
  self.phases = phases
  self.await_handlers = await_handlers
  self._turn_mgr = _build_turn_mgr(self)
  self._session = timing_session.new({
    game = game,
    phases = phases,
    turn_mgr = self._turn_mgr,
    script_factory = function(session)
      return timing_script.create(session, self.await_handlers)
    end,
  })
end

local function _sync_snapshot(runtime)
  local snapshot = runtime._session:snapshot()
  local turn = runtime.game and runtime.game.turn
  if type(turn) == "table" then
    if snapshot.wait_state then
      turn.phase = snapshot.wait_state
    elseif snapshot.current_state then
      turn.phase = snapshot.current_state
    end
  end
  return snapshot
end

function scheduler:dispatch(action)
  if action == nil then return end
  self._session.queue[#self._session.queue + 1] = { type = SIGNAL_ACTION, action = action }
  local res = self:step(0)
  _sync_snapshot(self)
  return res and res.wait_state or nil
end

function scheduler:run_turn()
  local res = self:step(0)
  _sync_snapshot(self)
  return res and res.wait_state or nil
end

local function _ensure_script(session)
  local script = session.script
  if script and coroutine.status(script) ~= "dead" then
    return script
  end
  session:reset_turn()
  script = session:create_script()
  session.script = script
  return script
end

local function _enqueue_tick_if_idle(session, dt)
  if #session.queue == 0 then
    session.queue[1] = { type = SIGNAL_TICK, dt = dt or 0 }
  end
end

local function _apply_tick(session, signal)
  if session.wait_state ~= "wait_choice" then
    return
  end
  session.choice_elapsed_seconds = session.choice_elapsed_seconds + signal.dt
  if session.game.turn then
    session.game.turn.choice_elapsed_seconds = session.choice_elapsed_seconds
  end
end

local function _apply_signal(session, signal)
  if signal.type == SIGNAL_ACTION then
    session:set_pending_action(signal.action)
    return
  end
  if signal.type == SIGNAL_TICK then
    _apply_tick(session, signal)
  end
end

local function _yielded_wait_state(yielded)
  if type(yielded) == "table" and yielded.kind == "wait" then
    return yielded.wait_state
  end
  return nil
end

local function _resume_script(session, script, signal)
  local ok, yielded = coroutine.resume(script, signal)
  if not ok then
    error(yielded)
  end
  if coroutine.status(script) == "dead" then
    session.finished = true
    session.wait_state = nil
    return { wait_state = nil, finished = true }, true
  end
  local wait_state = _yielded_wait_state(yielded)
  session.wait_state = wait_state
  return { wait_state = wait_state, finished = false }, false
end

function scheduler:step(dt)
  local session = self._session
  local script = _ensure_script(session)
  local queue = session.queue
  _enqueue_tick_if_idle(session, dt)
  local result
  while #queue > 0 do
    local signal = table.remove(queue, 1)
    _apply_signal(session, signal)
    local finished
    result, finished = _resume_script(session, script, signal)
    if finished then
      break
    end
  end
  return result or { wait_state = session.wait_state, finished = session.finished == true }
end

function scheduler:reset()
  self._session:reset_turn()
  self._session.queue = {}
  return _sync_snapshot(self)
end

return scheduler

