-- Choice resolution deliberately avoids requiring turn.actions.action_dispatcher;
-- dispatch entry points are provided by callers or by game:advance_turn.
local runtime_state = require("src.state.runtime")
local choice_auto_policy = require("src.turn.policies.choice_auto")
local fallback_registry = require("src.rules.choice.fallback_registry")
local choice_ports = require("src.turn.deadlines.choice_ports")
local choice_scope = require("src.turn.deadlines.choice_scope")

local choice_resolution = {}

local function _elapsed_from_entry(entry)
  return entry and entry.elapsed_seconds or nil
end

local function _elapsed_from_state(state)
  return runtime_state.get_pending_choice_elapsed(state) or 0
end

local function _resolve_choice_elapsed(api, state, choice)
  if type(state) ~= "table" then
    return 0
  end
  local entry_elapsed = _elapsed_from_entry(api.peek(state, choice_scope.for_choice(choice)))
  if entry_elapsed ~= nil then
    return entry_elapsed
  end
  return _elapsed_from_state(state)
end

local function _try_choice_auto(api, game, state, choice, precomputed_action)
  if precomputed_action ~= nil then
    return precomputed_action
  end
  local elapsed = _resolve_choice_elapsed(api, state, choice)
  return choice_auto_policy.decide(game, state, choice, {
    mode = "tick_timeout",
    elapsed_seconds = elapsed,
    min_visible_seconds = 0,
    allow_first_option_fallback = true,
  })
end

local function _dispatch_choice_action(game, state, choice, action)
  if not choice_ports.is_action_dispatchable(action) then
    return false
  end
  if action.choice_id == nil then
    action.choice_id = choice.id
  end
  choice_ports.ensure_actor_role_id(game, choice, action)
  choice_ports.dispatch_via_close_choice(game, state, action)
  return true
end

local function _resolve_fallback_choice_action(game, choice, action)
  if not (action == nil or (type(action) == "table" and action.type == "choice_force_skip")) then
    return nil
  end
  return fallback_registry.resolve(choice.kind, game, choice)
end

local function _dispatch_auto_or_fallback(api, game, state, choice, precomputed_action)
  local action = _try_choice_auto(api, game, state, choice, precomputed_action)
  if _dispatch_choice_action(game, state, choice, action) then
    return true
  end
  local fallback_action = _resolve_fallback_choice_action(game, choice, action)
  return _dispatch_choice_action(game, state, choice, fallback_action)
end

local function _invalid_choice(choice)
  return type(choice) ~= "table" or choice.id == nil
end

local function _resolve_reason(reason, fallback)
  return reason or fallback
end

function choice_resolution.install(api)
  function api.resolve_choice(game, state, choice, reason, precomputed_action)
    if _invalid_choice(choice) then
      api.force_skip(game, state, choice, _resolve_reason(reason, "no_choice"))
      return
    end
    if _dispatch_auto_or_fallback(api, game, state, choice, precomputed_action) then
      return
    end
    api.force_skip(game, state, choice, _resolve_reason(reason, "tick_timeout"))
  end

  local function _ctx_choice(target_ctx)
    if type(target_ctx) == "table" then
      return target_ctx.choice
    end
    return nil
  end

  local function _target_choice(target_ctx, game)
    local choice = _ctx_choice(target_ctx)
    if choice == nil and game and game.turn then
      return game.turn.pending_choice
    end
    return choice
  end

  function api.resolve_target_select(game, state, target_ctx, reason)
    api.force_skip(game, state, _target_choice(target_ctx, game), _resolve_reason(reason, "target_select_timeout"))
  end
end

return choice_resolution

