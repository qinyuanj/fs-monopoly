-- 回合阻塞/等待判定深模块:唯一判定器。
-- 「回合此刻被什么挡住(current_block)」与「带着一个目标 intent 该进入哪个 wait 态、
-- 如何挂 resume 回调(next_wait_state)」全部收敛于此。原先 land.lua 手搓的
-- anim×hold×move_anim×action_anim 组合路由(约130行 + 孪生 _resolve_finished_landing_state)
-- 迁入本模块;land 降为薄委托,保留其被 characterization 钉死的两个导出 seam。
local runtime_state = require("src.state.runtime")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local wait_callbacks = require("src.turn.waits.callback_registry")

local blocking = {}

local function _has_action_anim(game)
  if not game or not game.turn then
    return false
  end
  if game.turn.action_anim then
    return true
  end
  local queue = game.turn.action_anim_queue
  return type(queue) == "table" and #queue > 0
end

-- hold 状态以 state 为源时读其 active 标志;否则回落到 turn 上的标记。
local function _hold_state_active(game)
  local state = game.landing_visual_hold_state
  if state ~= nil and runtime_state.get_landing_visual_hold_source(state) ~= nil then
    return runtime_state.get_landing_visual_hold_active(state)
  end
  return nil
end

local function _turn_hold_active(game)
  local turn = game.turn or nil
  return turn and turn.landing_visual_hold_active == true or false
end

local function _is_landing_visual_hold_active(game)
  if not game then
    return false
  end
  local from_state = _hold_state_active(game)
  if from_state ~= nil then
    return from_state
  end
  return _turn_hold_active(game)
end

local _is_effect_idle = runtime_ports.is_effect_idle

local callback_keys = wait_callbacks.callback_keys

local function _register_action_anim_resume(game, next_state, next_args, callback)
  wait_callbacks.register(game, callback_keys.after_action_anim, callback)
  if next_state == "move_followup" then
    game.turn.move_followup_pending = true
  end
  return "wait_action_anim", {
    next_state = next_state,
    next_args = next_args,
  }
end

local function _register_landing_visual_resume(game, next_state, next_args, callback)
  wait_callbacks.register(game, callback_keys.after_landing_visual, callback)
  return "wait_landing_visual", {
    next_state = next_state,
    next_args = next_args,
  }
end

local function _resume_wait_choice(next_state, next_args)
  return "wait_choice", {
    next_state = next_state,
    next_args = next_args,
  }
end

local function _wait_for_choice_via(register_fn)
  return function(game, next_state, next_args)
    return register_fn(game, "wait_choice", {
      next_state = next_state,
      next_args = next_args,
    }, function()
      return _resume_wait_choice(next_state, next_args)
    end)
  end
end

local _wait_for_choice_via_action_anim = _wait_for_choice_via(_register_action_anim_resume)
local _wait_for_choice_via_landing_visual = _wait_for_choice_via(_register_landing_visual_resume)

local function _wait_for_choice_via_landing_visual_then_action_anim(game, next_state, next_args)
  local action_anim_state, action_anim_args = _wait_for_choice_via_action_anim(game, next_state, next_args)
  return _register_landing_visual_resume(game, action_anim_state, action_anim_args, function()
    return _wait_for_choice_via_action_anim(game, next_state, next_args)
  end)
end

local function _resolve_wait_move_anim(game, next_state, next_args, has_anim, has_hold_or_pending)
  if next_state == "move_followup" then game.turn.move_followup_pending = true end
  local move_anim_args = { next_state = next_state, next_args = next_args }
  local function _resume() return "wait_move_anim", move_anim_args end
  if has_anim then
    if has_hold_or_pending then
      return _register_landing_visual_resume(game, "wait_action_anim", {
        next_state = "wait_move_anim",
        next_args = move_anim_args,
      }, function()
        return _register_action_anim_resume(game, "wait_move_anim", move_anim_args, _resume)
      end)
    end
    return _register_action_anim_resume(game, "wait_move_anim", move_anim_args, _resume)
  end
  if has_hold_or_pending then return _register_landing_visual_resume(game, "wait_move_anim", move_anim_args, _resume) end
  return "wait_move_anim", move_anim_args
end

local function _resolve_wait_action_anim_state(game, next_state, next_args, has_anim, has_hold_or_pending)
  if has_anim then
    if has_hold_or_pending then
      return _register_landing_visual_resume(game, "wait_action_anim", {
        next_state = next_state,
        next_args = next_args,
      }, function()
        return _register_action_anim_resume(game, next_state, next_args, function() return next_state, next_args end)
      end)
    end
    return _register_action_anim_resume(game, next_state, next_args, function() return next_state, next_args end)
  end
  if has_hold_or_pending then
    return _register_landing_visual_resume(game, next_state, next_args, function() return next_state, next_args end)
  end
  return next_state, next_args
end

local function _route_choice_wait_state(game, has_anim, has_hold_or_pending, next_state, next_args)
  if has_anim then
    if has_hold_or_pending then return _wait_for_choice_via_landing_visual_then_action_anim(game, next_state, next_args) end
    return _wait_for_choice_via_action_anim(game, next_state, next_args)
  end
  if has_hold_or_pending then return _wait_for_choice_via_landing_visual(game, next_state, next_args) end
  return "wait_choice", { next_state = next_state, next_args = next_args }
end

-- 唯一等待判定器:给一个目标 (next_state,next_args) 与 wait 标志,
-- 按 action_anim / landing_visual_hold / effect_idle / move_anim 组合,
-- 决定进入哪个 wait 态并挂好 resume 回调。
function blocking.next_wait_state(game, next_state, next_args, wait_action_anim, wait_move_anim)
  local has_anim = _has_action_anim(game)
  local has_hold_or_pending = _is_landing_visual_hold_active(game) or not _is_effect_idle()
  if wait_move_anim == true then
    return _resolve_wait_move_anim(game, next_state, next_args, has_anim, has_hold_or_pending)
  end
  if wait_action_anim == true then
    return _resolve_wait_action_anim_state(game, next_state, next_args, has_anim, has_hold_or_pending)
  end
  return _route_choice_wait_state(game, has_anim, has_hold_or_pending, next_state, next_args)
end

local _PARKED_KINDS = {
  wait_landing_visual = "landing_visual",
  wait_action_anim = "action_anim",
  wait_move_anim = "move_anim",
  wait_choice = "choice",
  wait_action = "action",
}

-- 唯一「卡在什么上」查询:回合停在某个 wait 相时回报其 kind,否则 nil。
local function _turn_phase(game)
  local turn = game and game.turn or nil
  return turn and turn.phase or nil
end

local function _parked_kind(phase)
  return phase and _PARKED_KINDS[phase] or nil
end

function blocking.current_block(game)
  local kind = _parked_kind(_turn_phase(game))
  if kind == nil then
    return nil
  end
  return { kind = kind }
end

return blocking

