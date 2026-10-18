-- 回合调度 session 构造：pending action 存取、phase 标记、回合重置与快照。
-- 调度器信号泵与协程脚本由 src.turn.scheduler.runtime 私有协调。
local dirty_tracker = require("src.state.dirty_tracker")

local M = {}

local function _mark_phase_default(game, phase)
  if not (game and game.turn) then
    return
  end
  game.turn.phase = phase
  if game.dirty then
    dirty_tracker.mark(game.dirty, "turn")
  end
end

local function _build_session(opts)
  assert(type(opts) == "table", "missing session opts")
  assert(opts.game ~= nil, "missing session game")
  local s = {
    game = opts.game,
    phases = opts.phases,
    turn_mgr = opts.turn_mgr,
    script_factory = opts.script_factory,
    queue = {},
    script = nil,
    finished = false,
    wait_state = nil,
    current_state = "start",
    current_args = nil,
    choice_elapsed_seconds = 0,
    _pending_action = nil,
    _seconds_wait = {},
  }

  function s:set_pending_action(action)
    self._pending_action = action
  end

  function s:peek_pending_action()
    return self._pending_action
  end

  function s:take_pending_action()
    local action = self._pending_action
    self._pending_action = nil
    return action
  end

  function s:clear_pending_action()
    self._pending_action = nil
  end

  function s:mark_phase(phase)
    _mark_phase_default(self.game, phase)
  end

  function s:create_script()
    local factory = self.script_factory
    assert(type(factory) == "function", "missing session script_factory")
    return factory(self)
  end

  function s:reset_turn()
    self.current_state = "start"
    self.current_args = nil
    self.wait_state = nil
    self.finished = false
    self.script = nil
    self._seconds_wait = {}
    self.choice_elapsed_seconds = 0
    if self.game and self.game.turn then
      self.game.turn.choice_elapsed_seconds = 0
    end
    self:clear_pending_action()
  end

  -- choice_elapsed_seconds 在 snapshot() 中总被 self.choice_elapsed_seconds or 0 覆写，
  -- 模板不需要初值（等价变异体消除）。
  local _snapshot = { wait_state = nil, current_state = nil, pending_choice_id = nil }

  local function _pending_choice_id(turn)
    local pending_choice = turn and turn.pending_choice or nil
    return pending_choice and pending_choice.id or nil
  end

  function s:snapshot()
    local turn = self.game and self.game.turn or nil
    _snapshot.wait_state = self.wait_state
    _snapshot.current_state = self.current_state
    _snapshot.pending_choice_id = _pending_choice_id(turn)
    _snapshot.choice_elapsed_seconds = self.choice_elapsed_seconds or 0
    return _snapshot
  end

  return s
end

function M.new(opts)
  return _build_session(opts)
end

M._mark_phase_default = _mark_phase_default

return M

--[[ mutate4lua-manifest
version=4
projectHash=ba15909ed9056d86
scope.0.id=chunk:src/turn/scheduler/session.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=126
scope.0.semanticHash=656c0a3f4894547a
scope.1.id=function:_mark_phase_default
scope.1.kind=function
scope.1.startLine=7
scope.1.endLine=15
scope.1.semanticHash=cffe26f546b1609e
scope.2.id=function:_build_session
scope.2.kind=function
scope.2.startLine=17
scope.2.endLine=117
scope.2.semanticHash=5bdef563ac3fd05c
scope.3.id=function:s:set_pending_action
scope.3.kind=function
scope.3.startLine=37
scope.3.endLine=39
scope.3.semanticHash=e66f374cdcfa7616
scope.4.id=function:s:peek_pending_action
scope.4.kind=function
scope.4.startLine=41
scope.4.endLine=43
scope.4.semanticHash=c0484ae42c9068b0
scope.5.id=function:s:take_pending_action
scope.5.kind=function
scope.5.startLine=45
scope.5.endLine=49
scope.5.semanticHash=d2cd9de44dd0beb1
scope.6.id=function:s:clear_pending_action
scope.6.kind=function
scope.6.startLine=51
scope.6.endLine=53
scope.6.semanticHash=61b9ce27106ca232
scope.7.id=function:s:mark_phase
scope.7.kind=function
scope.7.startLine=55
scope.7.endLine=61
scope.7.semanticHash=b8c690fd2e45792e
scope.8.id=function:s:on_phase
scope.8.kind=function
scope.8.startLine=65
scope.8.endLine=76
scope.8.semanticHash=8dd2613b817e0e53
scope.9.id=function:<anonymous>
scope.9.kind=function
scope.9.startLine=68
scope.9.endLine=75
scope.9.semanticHash=e9a473c58c7bf055
scope.10.id=function:s:create_script
scope.10.kind=function
scope.10.startLine=78
scope.10.endLine=82
scope.10.semanticHash=d10f9f7202b16924
scope.11.id=function:s:reset_turn
scope.11.kind=function
scope.11.startLine=84
scope.11.endLine=96
scope.11.semanticHash=e59ca5f0a72b15e3
scope.12.id=function:_pending_choice_id
scope.12.kind=function
scope.12.startLine=102
scope.12.endLine=105
scope.12.semanticHash=93c839897afe61e5
scope.13.id=function:s:snapshot
scope.13.kind=function
scope.13.startLine=107
scope.13.endLine=114
scope.13.semanticHash=3eb719d861845648
scope.14.id=function:M.new
scope.14.kind=function
scope.14.startLine=119
scope.14.endLine=121
scope.14.semanticHash=f1ce1850b7232305
]]
