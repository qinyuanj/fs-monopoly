local synthetic_actor_registry = require("src.host.synthetic_actor_registry")
require("src.config.content.runtime_refs")

local runtime_context = {}
local game_api_key = "Game" .. "API"

local current_context = nil

local function _resolve_game_api_instance(get_game_api)
  if type(get_game_api) ~= "function" then
    return nil
  end
  return get_game_api()
end

local function _resolve_game_api_roles(get_game_api)
  local game_api = _resolve_game_api_instance(get_game_api)
  if not (game_api and type(game_api.get_all_valid_roles) == "function") then
    return {}
  end
  local ok, valid_roles = pcall(game_api.get_all_valid_roles)
  if not ok or type(valid_roles) ~= "table" then
    return {}
  end
  return valid_roles
end

function runtime_context.new(env)
  return {
    env = env or {},
    roles = nil,
    camera_helper = nil,
    synthetic_actor_registry = nil,
  }
end

function runtime_context.set_current(ctx)
  current_context = ctx
  return ctx
end

function runtime_context.current()
  return current_context
end

-- 各宿主端口共用同一份当前 env 读取，避免分别解释上下文缺失时的降级语义。
function runtime_context.current_api(context_source, env_key)
  local ctx = context_source.current and context_source.current() or nil
  local env = ctx and ctx.env or nil
  return env and env[env_key] or nil
end

local function _refresh_roles(ctx)
  assert(ctx ~= nil and ctx.env ~= nil, "missing runtime context")
  ctx.roles = _resolve_game_api_roles(function()
    return ctx.env and ctx.env[game_api_key] or nil
  end)
  return ctx.roles
end

function runtime_context.install_globals(ctx)
  assert(ctx ~= nil and ctx.env ~= nil, "missing runtime context")
  runtime_context.install_environment(ctx)
  runtime_context.install_runtime_helpers(ctx, { install_globals = true })
end

local _required_lua_api_methods = {
  "call_delay_time",
  "global_register_custom_event",
  "global_register_trigger_event",
  "global_unregister_trigger_event",
  "unit_register_custom_event",
  "unit_register_trigger_event",
  "global_send_custom_event",
}

function runtime_context.validate_lua_api_methods(lua_api, required_methods)
  assert(lua_api ~= nil, "missing LuaAPI")
  for _, name in ipairs(required_methods) do
    assert(type(lua_api[name]) == "function", "missing LuaAPI." .. name)
  end
  return lua_api
end

function runtime_context.install_environment(ctx)
  assert(ctx ~= nil and ctx.env ~= nil, "missing runtime context")
  local lua_api = ctx.env.LuaAPI
  runtime_context.validate_lua_api_methods(lua_api, _required_lua_api_methods)
  return ctx.env
end

local function _ensure_runtime_helper_fields(ctx)
  if not ctx.camera_helper then
    ctx.camera_helper = require("src.host.camera").new(ctx.env)
  end
  if not ctx.synthetic_actor_registry then
    ctx.synthetic_actor_registry = synthetic_actor_registry.new(ctx.env)
  end
  if not ctx.roles then
    _refresh_roles(ctx)
  end
end

function runtime_context.install_runtime_helpers(ctx, opts)
  assert(ctx ~= nil, "missing runtime context")
  opts = opts or {}
  _ensure_runtime_helper_fields(ctx)
  local helpers = {
    camera_helper = ctx.camera_helper,
    roles = ctx.roles,
  }
  if opts.install_globals then
    runtime_context.install_runtime_helper_globals(helpers)
  end
  return helpers
end

function runtime_context.install_runtime_helper_globals(helpers)
  assert(helpers ~= nil, "missing helpers")
  camera_helper = helpers.camera_helper
  all_roles = helpers.roles
  ALLROLES = helpers.roles
  return helpers
end

return runtime_context

