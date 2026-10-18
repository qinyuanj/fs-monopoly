local wait_callbacks = require("src.turn.waits.callback_registry")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local shared = require("src.turn.waits.await_shared")

local _WAIT = shared.WAIT
local _unpack_next = shared.unpack_next
local _mark_dirty = shared.mark_dirty

local callback_keys = wait_callbacks.callback_keys
local anim_done_timeout_seconds = 10.0

local _next_action_anim

local function _resolve_action_anim_wait(game)
  local anim = game.turn.action_anim
  if anim then
    -- 第二返回值只在 anim 缺失时被消费(_resolve_action_anim_idle 先判
    -- anim ~= nil),anim 在场时恒不被读——false 字面值是死位(等价变异体)。
    return anim
  end
  local next_anim = _next_action_anim(game)
  return next_anim, next_anim ~= nil
end

local function _resolve_action_anim_idle(session, args, _, anim, queued_next_anim)
  if anim ~= nil then
    return nil
  end
  if queued_next_anim then
    return _WAIT
  end
  session:clear_pending_action()
  local next_state, next_args = _unpack_next(args)
  return {
    next_state = next_state,
    next_args = next_args,
  }
end

local function _is_anim_timed_out(anim)
  if not anim or not anim.started_at then
    return false
  end
  local elapsed = runtime_ports.wall_diff_seconds(runtime_ports.wall_now_seconds(), anim.started_at)
  local timeout = (anim.duration or 2.0) + anim_done_timeout_seconds
  return elapsed >= timeout
end

local function _seq_mismatch(action, anim)
  return action.seq and anim.seq and action.seq ~= anim.seq
end

local function _is_matching_done_action(action, anim, action_type)
  if not action or action.type ~= action_type then
    return false
  end
  if _seq_mismatch(action, anim) then
    return false
  end
  return true
end

local function _complete_action_anim(session, args, game)
  game.turn.action_anim = nil
  _mark_dirty(game)
  if _next_action_anim(game) then
    return _WAIT
  end
  session:clear_pending_action()
  local next_state, next_args = _unpack_next(args)
  return {
    next_state = next_state,
    next_args = next_args,
  }
end

local function _is_cash_receive_anim(anim)
  return anim and anim.kind == "cash_receive"
end

local function _cash_receive_merge_end(queue)
  for i = 2, #queue do
    if not _is_cash_receive_anim(queue[i]) then
      return i - 1
    end
  end
  return #queue
end

local function _cash_receive_total(queue, merge_end)
  local total_amount = queue[1].amount or 0
  for i = 2, merge_end do
    total_amount = total_amount + (queue[i].amount or 0)
  end
  return total_amount
end

local function _remove_coalesced_actions(queue, merge_end)
  for _ = 2, merge_end do
    table.remove(queue, 2)
  end
end

local function _coalesce_head(queue)
  if #queue < 2 then
    return
  end
  local head = queue[1]
  if not _is_cash_receive_anim(head) then
    return
  end
  local merge_end = _cash_receive_merge_end(queue)
  if merge_end <= 1 then
    return
  end
  head.amount = _cash_receive_total(queue, merge_end)
  head.coalesced_count = merge_end
  _remove_coalesced_actions(queue, merge_end)
end

_next_action_anim = function(game)
  -- game 与 game.turn 恒非 nil(两个调用方都先读写 game.turn 才到这里),
  -- 曾经的入口断言恒不触发——等价变异体,按 #257 三分类删冗余。
  local queue = game.turn.action_anim_queue
  if type(queue) ~= "table" or #queue == 0 then
    return nil
  end
  _coalesce_head(queue)
  local anim = table.remove(queue, 1)
  anim.started_at = runtime_ports.wall_now_seconds()
  game.turn.action_anim = anim
  _mark_dirty(game)
  return anim
end

-- 动画收尾后若挂了 after_action_anim 回调，用回调结果接续状态机。
local function _resume_after_action_anim(game, completed)
  local continuation = wait_callbacks.take(game, callback_keys.after_action_anim)
  if continuation == nil then
    return completed
  end
  local next_state, next_args = continuation()
  return {
    next_state = next_state,
    next_args = next_args,
  }
end

local function _should_wait_anim(action, anim)
  return not _is_anim_timed_out(anim) and not _is_matching_done_action(action, anim, "action_anim_done")
end

local function _completed_wait(completed)
  return completed ~= nil and completed.wait == true
end

local function _action_anim(session, args)
  assert(session ~= nil and session.game ~= nil, "missing await session")
  local game = session.game
  session:mark_phase("wait_action_anim")
  local anim, queued_next_anim = _resolve_action_anim_wait(game)
  local idle_res = _resolve_action_anim_idle(session, args, game, anim, queued_next_anim)
  if idle_res ~= nil then
    return idle_res
  end

  local action = session:take_pending_action()
  if _should_wait_anim(action, anim) then
    return _WAIT
  end
  local completed = _complete_action_anim(session, args, game)
  if _completed_wait(completed) then
    return completed
  end
  return _resume_after_action_anim(game, completed)
end

local action_anim = {}

action_anim.action_anim = _action_anim
action_anim._coalesce_head = _coalesce_head

return action_anim

