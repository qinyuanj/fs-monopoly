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

