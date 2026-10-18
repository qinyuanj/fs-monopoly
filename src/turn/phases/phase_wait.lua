local phase_wait = {}

local function _default_args(player, total, raw_total)
  return {
    player = player,
    total = total,
    raw_total = raw_total,
  }
end

local function _next_args_of(phase_res, player, total, raw_total)
  local next_args = phase_res and phase_res.next_args or nil
  if next_args == nil then
    return _default_args(player, total, raw_total)
  end
  return next_args
end

function phase_wait.resolve_result(phase_res, default_next_state, player, total, raw_total)
  local next_state = phase_res and phase_res.next_state or default_next_state
  local next_args = _next_args_of(phase_res, player, total, raw_total)
  if phase_res and phase_res.wait_action_anim == true then
    return "wait_action_anim", {
      next_state = next_state,
      next_args = next_args,
    }
  end
  return "wait_choice", {
    next_state = next_state,
    next_args = next_args,
  }
end

return phase_wait

