local move_anim_debug = require("src.foundation.move_anim_debug")
local shared = require("src.turn.waits.await_shared")

local _WAIT = shared.WAIT
local _unpack_next = shared.unpack_next
local _mark_dirty = shared.mark_dirty

local function _session_game(session)
  return session and session.game or nil
end

local function _turn_from_game(game)
  return game and game.turn or nil
end

local function _turn_anim(turn, anim_key)
  return turn and turn[anim_key] or nil
end

local function _peek_pending_action(session)
  return session and session.peek_pending_action and session:peek_pending_action() or nil
end

local function _field_text(source, key)
  return tostring(source and source[key] or "nil")
end

local function _log_move_anim_wait(session, opts)
  local game = _session_game(session)
  opts = opts or {}
  local anim_key = opts.anim_key or "move_anim"
  local turn = _turn_from_game(game)
  local anim = _turn_anim(turn, anim_key)
  local action = _peek_pending_action(session)
  move_anim_debug.log(
    "await_move_anim",
    "phase=" .. _field_text(turn, "phase"),
    "anim_seq=" .. _field_text(anim, "seq"),
    "pending_action_type=" .. _field_text(action, "type"),
    "pending_action_seq=" .. _field_text(action, "seq")
  )
end

local _cached_anim_opts = {
  state_name = nil,
  anim_key = nil,
  done_action_type = nil,
}

local function _opt_or(opts, key, fallback)
  return opts and opts[key] or fallback
end

local function _resolve_wait_anim_opts(opts)
  _cached_anim_opts.state_name = _opt_or(opts, "state_name", "wait_move_anim")
  _cached_anim_opts.anim_key = _opt_or(opts, "anim_key", "move_anim")
  _cached_anim_opts.done_action_type = _opt_or(opts, "done_action_type", "move_anim_done")
  return _cached_anim_opts
end

local function _assert_await_anim_args(session, opts)
  assert(session ~= nil and session.game ~= nil, "missing await session")
  -- opts 三件套(state_name/anim_key/done_action_type)恒被唯一调用方
  -- _resolve_wait_anim_opts 填满,曾经的三个 nil 断言恒不触发——
  -- 等价变异体,按 #257 三分类删冗余。
end

-- action 是否是本次动画的完成信号：类型匹配，且 seq 不与动画冲突。
local function _is_anim_done_action(action, anim, done_action_type)
  if not action or action.type ~= done_action_type then
    return false
  end
  return not (action.seq and anim.seq and action.seq ~= anim.seq)
end

local function _await_anim_done(session, args, opts)
  _assert_await_anim_args(session, opts)
  local game = session.game
  session:mark_phase(opts.state_name)
  local anim = game.turn[opts.anim_key]
  assert(anim ~= nil, "missing " .. tostring(opts.anim_key))
  local action = session:take_pending_action()
  if not _is_anim_done_action(action, anim, opts.done_action_type) then
    return _WAIT
  end
  game.turn[opts.anim_key] = nil
  _mark_dirty(game)
  local next_state, next_args = _unpack_next(args)
  return { next_state = next_state, next_args = next_args }
end

local move_anim = {}

function move_anim.move_anim(session, args, opts)
  if move_anim_debug.enabled() then
    _log_move_anim_wait(session, opts)
  end
  return _await_anim_done(session, args, _resolve_wait_anim_opts(opts))
end

return move_anim

