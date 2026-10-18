local turn_anim = {}
local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_state = require("src.state.runtime")
local logger = require("src.foundation.log")

local _move_anim_opts = {
  anim_key = "move_anim",
  phase = "wait_move_anim",
  phase_label = "move anim",
  seq_key = "move_anim_seq",
  done_action = "move_anim_done",
  on_anim = nil,
}

local _action_anim_opts = {
  anim_key = "action_anim",
  phase = "wait_action_anim",
  phase_label = "action anim",
  seq_key = "action_anim_seq",
  done_action = "action_anim_done",
  on_anim = nil,
}

local function _resolve_validated_anim(game, opts)
  local anim = game.turn[opts.anim_key]
  local phase = game.turn.phase
  assert(anim and anim.seq, "missing " .. tostring(opts.anim_key))

  local phase_label = opts.phase_label or "anim"
  assert(phase == opts.phase, "unexpected " .. phase_label .. " phase: " .. tostring(phase))
  return anim
end

local function _dispatch_anim_done(game, opts, anim)
  assert(game.dispatch_action, "missing game.dispatch_action")
  game:dispatch_action({ type = opts.done_action, seq = anim.seq })
end

-- on_anim 结果分派:失败留痕(warn 带标识与错误)但行为保持——仍走
-- done 分支;成功且正延迟才进 schedule(ADR 0046「跳过必留痕」,#339)。
local function _finish_step_anim(game, opts, anim, ok, delay)
  if not ok then
    logger.warn("[turn.anim]", "on_anim failed for seq=" .. tostring(opts.seq_key)
      .. " anim=" .. tostring(opts.anim_key or "?")
      .. ": " .. tostring(delay))
  elseif delay and delay > 0 then
    runtime_ports.schedule(delay, function()
      _dispatch_anim_done(game, opts, anim)
    end)
    return
  end
  _dispatch_anim_done(game, opts, anim)
end

local function _step_anim(game, state, opts)
  assert(game, "missing game")
  assert(opts, "missing opts")
  assert(opts.on_anim, "missing opts.on_anim")
  assert(opts.anim_key, "missing opts.anim_key")
  assert(opts.phase, "missing opts.phase")
  assert(opts.seq_key, "missing opts.seq_key")
  assert(opts.done_action, "missing opts.done_action")

  local anim = _resolve_validated_anim(game, opts)

  local anim_runtime = runtime_state.ensure_anim_runtime(state)
  if anim_runtime[opts.seq_key] == anim.seq then
    return
  end

  anim_runtime[opts.seq_key] = anim.seq
  _finish_step_anim(game, opts, anim, pcall(opts.on_anim, state, anim))
end

local function _step_anim_kind(kind_opts, wait_field, on_anim_key)
  return function(game, state, opts)
    assert(state[wait_field] == true, kind_opts.phase_label .. " disabled")
    assert(opts ~= nil and opts[on_anim_key] ~= nil, "missing opts." .. on_anim_key)
    kind_opts.on_anim = opts[on_anim_key]
    _step_anim(game, state, kind_opts)
  end
end

turn_anim.step_move_anim = _step_anim_kind(_move_anim_opts, "wait_move_anim", "on_move_anim")
turn_anim.step_action_anim = _step_anim_kind(_action_anim_opts, "wait_action_anim", "on_action_anim")

return turn_anim

