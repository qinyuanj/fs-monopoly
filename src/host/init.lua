local runtime_ports = require("src.foundation.ports.runtime_ports")
local runtime_context = require("src.host.context")
local tip_queue = require("src.foundation.tips")
local role_resolver = require("src.host.role_resolver")
local unit_lifecycle = require("src.host.units")
local entity_pool = require("src.host.entity_pool")
local scene_ui = require("src.host.scene_ui")
local sfx_runtime = require("src.host.sound")

local host_runtime = {}

-- 取当前 runtime context 上的 LuaAPI 表:context 未装载或 env 无 LuaAPI 时
-- 统一 nil,调用方据此走各自的降级返回值。
local function _host_lua_api()
  local runtime_ctx = runtime_context.current()
  return runtime_ctx and runtime_ctx.env and runtime_ctx.env.LuaAPI or nil
end

-- 取宿主 LuaAPI 上的具名函数句柄:context 未装载、env 无 LuaAPI、
-- 或宿主未提供该函数时统一返回 nil,调用方据此走各自的降级返回值。
local function lua_api_fn(fn_name)
  local lua_api = _host_lua_api()
  if not (lua_api and type(lua_api[fn_name]) == "function") then
    return nil
  end
  return lua_api[fn_name]
end

function host_runtime.schedule(delay, fn)
  return runtime_ports.schedule(delay or 0, fn)
end

host_runtime.enqueue_tip = tip_queue.enqueue

function host_runtime.register_custom_event(event_name, handler)
  if type(event_name) ~= "string" or type(handler) ~= "function" then
    return false
  end
  local register = lua_api_fn("global_register_custom_event")
  if not register then
    return false
  end
  -- Return the trigger handle as a second value so callers that need the
  -- host trigger id (e.g. ENode event listeners) can capture it, while
  -- existing boolean-asserting callers keep seeing `true`.
  return true, register(event_name, handler)
end

function host_runtime.unregister_custom_event(trigger)
  if trigger == nil then
    return false
  end
  local unregister = lua_api_fn("global_unregister_custom_event")
  if not unregister then
    return false
  end
  unregister(trigger)
  return true
end

-- 注册宿主触发器事件(事件名+注册参数的数组形态,如 {ET_SPEC_ROLE_EXIT_GAME, role})。
-- 回调签名 (event_name, actor, data) 以 EggyAPI 注解为线索,逐事件真机取证。
function host_runtime.register_trigger_event(event_desc, handler)
  if type(event_desc) ~= "table" or type(handler) ~= "function" then
    return false
  end
  local register = lua_api_fn("global_register_trigger_event")
  if not register then
    return false
  end
  return true, register(event_desc, handler)
end

-- #199:输入框「输入完成」触发器(注册参数为 EInputField 节点 id,回调 data 带
-- role / content)。事件名取运行时 EVENT 表的值(注解裸名可能与运行时值不同,
-- 参照 #585);EVENT 缺该字段时视为端口不可用返回 false。
function host_runtime.register_input_text_end(node_id, handler)
  local event_name = EVENT and EVENT.UI_INPUT_TEXT_END_EVENT or nil
  if event_name == nil or node_id == nil then
    return false
  end
  return host_runtime.register_trigger_event({ event_name, node_id }, handler)
end

function host_runtime.query_units(names)
  local query = lua_api_fn("query_units")
  if not query then
    return nil
  end
  return query(names)
end

function host_runtime.query_unit(name)
  local query = lua_api_fn("query_unit")
  if not query then
    return nil
  end
  return query(name)
end

function host_runtime.resolve_role_with(player_id, predicate)
  return role_resolver.resolve_role_with(player_id, predicate)
end

function host_runtime.resolve_roles()
  return role_resolver.resolve_roles()
end

host_runtime.create_unit_group = unit_lifecycle.create_unit_group
host_runtime.create_unit_with_scale = unit_lifecycle.create_unit_with_scale
host_runtime.destroy_unit_with_children = unit_lifecycle.destroy_unit_with_children
host_runtime.destroy_unit = unit_lifecycle.destroy_unit

host_runtime.acquire_unit = entity_pool.acquire
host_runtime.release_unit = entity_pool.release
host_runtime.prewarm_unit = entity_pool.prewarm

host_runtime.play_sfx_by_key = sfx_runtime.play_sfx_by_key
host_runtime.play_3d_sound = sfx_runtime.play_3d_sound
host_runtime.bind_sfx_to_unit = sfx_runtime.bind_sfx_to_unit

host_runtime.set_scene_ui_visible = scene_ui.set_scene_ui_visible
host_runtime.destroy_scene_ui = scene_ui.destroy_scene_ui
host_runtime.has_scene_ui_support = scene_ui.has_scene_ui_support
host_runtime.get_eui_node_at_scene_ui = scene_ui.get_eui_node_at_scene_ui

return host_runtime

