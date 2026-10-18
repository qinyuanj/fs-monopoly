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

--[[ mutate4lua-manifest
version=4
projectHash=7a8a818cd0d3b611
scope.0.id=chunk:src/turn/scheduler/runtime.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=173
scope.0.semanticHash=2d13f41bd8e5d966
scope.1.id=function:_emit_turn_prompt
scope.1.kind=function
scope.1.startLine=18
scope.1.endLine=22
scope.1.semanticHash=7bf9e0729fa45f91
scope.2.id=function:_next_player
scope.2.kind=function
scope.2.startLine=24
scope.2.endLine=32
scope.2.semanticHash=05d0223d06de6744
scope.3.id=function:_build_turn_mgr
scope.3.kind=function
scope.3.startLine=34
scope.3.endLine=42
scope.3.semanticHash=fe3c37a7008daca1
scope.4.id=function:<anonymous>
scope.4.kind=function
scope.4.startLine=38
scope.4.endLine=40
scope.4.semanticHash=7bbf31ab6751de78
scope.5.id=function:scheduler:init
scope.5.kind=function
scope.5.startLine=44
scope.5.endLine=60
scope.5.semanticHash=b8ba9b10be52be2f
scope.6.id=function:<anonymous>#2
scope.6.kind=function
scope.6.startLine=55
scope.6.endLine=57
scope.6.semanticHash=d62e2c377e650a89
scope.7.id=function:_sync_snapshot
scope.7.kind=function
scope.7.startLine=62
scope.7.endLine=73
scope.7.semanticHash=e6fdf7d3f0cd78e6
scope.8.id=function:scheduler:dispatch
scope.8.kind=function
scope.8.startLine=75
scope.8.endLine=81
scope.8.semanticHash=f92256844c754791
scope.9.id=function:scheduler:run_turn
scope.9.kind=function
scope.9.startLine=83
scope.9.endLine=87
scope.9.semanticHash=2afca5c4a0977eef
scope.10.id=function:_ensure_script
scope.10.kind=function
scope.10.startLine=89
scope.10.endLine=98
scope.10.semanticHash=6f65760a68690d3d
scope.11.id=function:_enqueue_tick_if_idle
scope.11.kind=function
scope.11.startLine=100
scope.11.endLine=104
scope.11.semanticHash=44ded4804d44ea65
scope.12.id=function:_apply_tick
scope.12.kind=function
scope.12.startLine=106
scope.12.endLine=114
scope.12.semanticHash=e80a44977ab9941e
scope.13.id=function:_apply_signal
scope.13.kind=function
scope.13.startLine=116
scope.13.endLine=124
scope.13.semanticHash=97d250487efcf0fd
scope.14.id=function:_yielded_wait_state
scope.14.kind=function
scope.14.startLine=126
scope.14.endLine=131
scope.14.semanticHash=3e82050f2a5ecaf9
scope.15.id=function:_resume_script
scope.15.kind=function
scope.15.startLine=133
scope.15.endLine=146
scope.15.semanticHash=fb4d14d44ded09a9
scope.16.id=function:scheduler:step
scope.16.kind=function
scope.16.startLine=148
scope.16.endLine=164
scope.16.semanticHash=09e4082c1b35a5a1
scope.17.id=function:scheduler:reset
scope.17.kind=function
scope.17.startLine=166
scope.17.endLine=170
scope.17.semanticHash=e79fe663c0e8f997
]]
