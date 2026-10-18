local monopoly_event = require("src.foundation.events")
local host_runtime = require("src.host.init")
local landing_visual_hold = require("src.ui.visual_hold")
local runtime_event_ports = require("src.ui.ports.events")

local M = {}
local registered_triggers = {}

function M.install(state, get_current_game)
  assert(state ~= nil, "missing state")
  assert(type(get_current_game) == "function", "missing get_current_game")
  if #registered_triggers > 0 then
    return
  end

  local function _dispatch_or_defer(data, handler)
    local current_game = get_current_game()
    state.game = current_game
    landing_visual_hold.run_or_defer(state, nil, "runtime_event", function()
      handler(data)
    end)
  end

  -- 走 host seam 注册:宿主 LuaAPI 的取用与函数存在性校验归 src.host.init 独有,
  -- app 层不再自己穿 runtime ctx -> env -> LuaAPI(ui 侧对应面是 src.ui.seams.host_events)。
  local function _register_event(event_name, handler_fn)
    local registered, trigger = host_runtime.register_custom_event(event_name, function(_, _, data)
      _dispatch_or_defer(data, handler_fn)
    end)
    assert(registered, "missing LuaAPI.global_register_custom_event")
    registered_triggers[#registered_triggers + 1] = trigger
  end

  local ok, err = pcall(function()
    _register_event(monopoly_event.land.tile_upgraded, function(payload)
      runtime_event_ports.on_tile_upgraded(state, payload)
    end)

    _register_event(monopoly_event.intent.need_choice, function(payload)
      runtime_event_ports.on_need_choice(state, get_current_game, payload)
    end)
  end)
  if not ok then
    M.uninstall()
    error(err, 0)
  end
end

function M.uninstall()
  for index = #registered_triggers, 1, -1 do
    host_runtime.unregister_custom_event(registered_triggers[index])
    registered_triggers[index] = nil
  end
end

return M

