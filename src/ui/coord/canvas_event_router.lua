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

--[[ mutate4lua-manifest
version=4
projectHash=bc0b804096336908
scope.0.id=chunk:src/ui/coord/canvas_event_router.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=130
scope.0.semanticHash=cd938057bcb798e5
scope.1.id=function:_destroy_listener
scope.1.kind=function
scope.1.startLine=14
scope.1.endLine=18
scope.1.semanticHash=2b5f5e7dac6e6713
scope.2.id=function:_clear_compat_fields
scope.2.kind=function
scope.2.startLine=20
scope.2.endLine=23
scope.2.semanticHash=0e497c7579c16b27
scope.3.id=function:_take_scope
scope.3.kind=function
scope.3.startLine=25
scope.3.endLine=29
scope.3.semanticHash=d2cd9de44dd0beb1
scope.4.id=function:_track_new_listeners
scope.4.kind=function
scope.4.startLine=31
scope.4.endLine=39
scope.4.semanticHash=db8d119a47c86f7f
scope.5.id=function:<anonymous>
scope.5.kind=function
scope.5.startLine=34
scope.5.endLine=36
scope.5.semanticHash=600a75ce96a391b3
scope.6.id=function:router.destroy
scope.6.kind=function
scope.6.startLine=41
scope.6.endLine=56
scope.6.semanticHash=f020bd335759afc0
scope.7.id=function:_rollback_bind
scope.7.kind=function
scope.7.startLine=58
scope.7.endLine=66
scope.7.semanticHash=b3fd95d0330db026
scope.8.id=function:<anonymous>#2
scope.8.kind=function
scope.8.startLine=59
scope.8.endLine=61
scope.8.semanticHash=600a75ce96a391b3
scope.9.id=function:router.bind
scope.9.kind=function
scope.9.startLine=68
scope.9.endLine=127
scope.9.semanticHash=daafd794676e4c69
scope.10.id=function:<anonymous>#3
scope.10.kind=function
scope.10.startLine=76
scope.10.endLine=78
scope.10.semanticHash=c772a22f8680e278
scope.11.id=function:dispatch_intent
scope.11.kind=function
scope.11.startLine=81
scope.11.endLine=90
scope.11.semanticHash=30714e21ae0fd830
scope.12.id=function:track_new_listeners
scope.12.kind=function
scope.12.startLine=99
scope.12.endLine=101
scope.12.semanticHash=c2df8db3a1e93eb5
scope.13.id=function:<anonymous>#4
scope.13.kind=function
scope.13.startLine=103
scope.13.endLine=121
scope.13.semanticHash=6cc84023ea740c45
scope.14.id=function:<anonymous>#5
scope.14.kind=function
scope.14.startLine=107
scope.14.endLine=112
scope.14.semanticHash=a0d651310b388925
]]
