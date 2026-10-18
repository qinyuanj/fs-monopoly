local ui_event_bindings = require("src.ui.coord.event_bindings")
local ui_intent_dispatcher = require("src.ui.input.intent_dispatcher")
local canvas_registry = require("src.ui.input.routes")
local event_actor_policy = require("src.ui.coord.event_actor_policy")
local modal = require("src.ui.coord.modal")
local base_nodes = require("src.ui.schema.base")
local Scope = require("src.foundation.scope")
local logger = require("src.foundation.log")
local command_policy = require("src.ui.input.command_policy")
local afk_signal = require("src.turn.policies.afk_signal")

local router = {}

local function _destroy_listener(listener)
  if listener and listener.destroy then
    listener:destroy()
  end
end

local function _take_scope(state)
  local scope = state.ui_event_router_scope
  state.ui_event_router_scope = nil
  return scope
end

local function _track_new_listeners(scope, listeners, tracked_count)
  for index = tracked_count + 1, #listeners do
    local listener = listeners[index]
    scope:defer(function()
      _destroy_listener(listener)
    end)
  end
  return #listeners
end

function router.destroy(state)
  assert(state ~= nil, "missing state")
  local scope = _take_scope(state)
  if scope ~= nil then
    scope:destroy()
  end
end

local function _rollback_bind(state, original_err)
  local ok, cleanup_err = pcall(function()
    router.destroy(state)
  end)
  if not ok then
    logger.warn("ui event router rollback cleanup failed:", tostring(cleanup_err))
  end
  error(original_err, 0)
end

function router.bind(state, resolve_game)
  assert(state ~= nil, "missing state")
  router.destroy(state)

  local scope = Scope.new()
  state.ui_event_router_scope = scope

  local dispatch_opts = {
    on_close_choice = function(ctx)
      modal.close_choice_modal(ctx)
    end,
  }

  local function dispatch_intent(intent, data)
    if not event_actor_policy.attach_event_actor(state, intent, data) then
      return
    end
    local game = resolve_game()
    if command_policy.game_handler(intent) ~= nil and intent.actor_role_id ~= nil then
      afk_signal.on_real_input(game, state, intent.actor_role_id)
    end
    ui_intent_dispatcher.dispatch(state, game, intent, dispatch_opts)
  end

  local cache = {}
  local registered = {}
  local listeners = {}

  local tracked_count = 0
  local function track_new_listeners()
    tracked_count = _track_new_listeners(scope, listeners, tracked_count)
  end

  local ok, err = pcall(function()
    local route_specs = canvas_registry.build_route_specs(state)
    for _, route in ipairs(route_specs) do
      local route_name = route.name
      ui_event_bindings.register_node_click(cache, route_name, function(data)
        local intent = route.build_intent(data)
        if intent then
          dispatch_intent(intent, data)
        end
      end, registered, listeners, {
        bind_client_role = route_name ~= base_nodes.action_log_button,
      })
      track_new_listeners()
    end

    ui_event_bindings.enable_action_log_toggle_touch(cache, state.ui)
    ui_event_bindings.register_missing_button_tip(cache, registered, listeners)
    track_new_listeners()
  end)

  if not ok then
    track_new_listeners()
    _rollback_bind(state, err)
  end
end

return router

