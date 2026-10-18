local M = {}

function M.patch(next_state, next_args, match_state, default_next_state, default_next_args)
  if next_state ~= match_state or type(next_args) ~= "table" then
    return next_state, next_args
  end
  next_args.next_state = next_args.next_state or default_next_state
  next_args.next_args = next_args.next_args or default_next_args
  return next_state, next_args
end

local function _after_action_anim_table(res)
  if type(res) ~= "table" then
    return nil
  end
  local after_action_anim = res.after_action_anim
  if type(after_action_anim) ~= "table" then
    return nil
  end
  return after_action_anim
end

function M.resolve_after_action_anim(args, res, match_state)
  args = args or {}
  local default_next_state = args.next_state
  local default_next_args = args.next_args
  local after_action_anim = _after_action_anim_table(res)
  if after_action_anim == nil then
    return default_next_state, default_next_args
  end
  return M.patch(
    after_action_anim.next_state or default_next_state,
    after_action_anim.next_args or default_next_args,
    match_state,
    default_next_state,
    default_next_args
  )
end

return M

