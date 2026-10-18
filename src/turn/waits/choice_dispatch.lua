local owner = require("src.turn.choice.owner")

local choice_dispatch = {}

function choice_dispatch.resolve_choice_owner_id(game, choice)
  return owner.resolve_role_id(game, choice)
end

function choice_dispatch.ensure_action_actor_role_id(game, choice, action)
  return owner.ensure_actor_role_id(game, choice, action)
end

function choice_dispatch.dispatch_choice_tick_action(game, state, choice, output_ports, opts, payload)
  local action = opts.build_action(game, state, choice, payload)
  if not action then
    return false
  end
  choice_dispatch.ensure_action_actor_role_id(game, choice, action)
  output_ports.set_pending_choice_elapsed(state, 0)
  opts.dispatch_action_with_close_choice(game, state, action)
  return true
end

return choice_dispatch

