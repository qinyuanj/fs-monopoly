-- runtime_ports 的宿主默认实现装配(>100 mutation sites 拆分):时钟族
-- clock_ports / 角色族 role_ports / 档案族 archive_ports 各自成模块,
-- 本文件保留 build 骨架与零散默认(随机数/调度/相机/事件/整局结束/特效查询)。
local clock_ports = require("src.host.clock_ports")
local role_ports = require("src.host.role_ports")
local archive_ports = require("src.host.archive_ports")
local logger = require("src.foundation.log")
local host_context = require("src.host.context")

local default_ports = {}
local game_api_key = "Game" .. "API"
local lua_api_key = "Lua" .. "API"

function default_ports.build(runtime_context)
  local defaults = {}

  clock_ports.install(defaults, runtime_context)
  role_ports.install(defaults, runtime_context)
  archive_ports.install(defaults, runtime_context)

  function defaults.rng_next_int(min, max)
    assert(min ~= nil and max ~= nil, "rng.next_int requires min/max")
    local game_api = host_context.current_api(runtime_context, game_api_key)
    assert(game_api and game_api.random_int, "missing game api random_int")
    return game_api.random_int(min, max)
  end

  function defaults.schedule(delay, fn)
    assert(type(fn) == "function", "schedule requires callback")
    local lua_api = host_context.current_api(runtime_context, lua_api_key)
    if lua_api and type(lua_api.call_delay_time) == "function" then
      lua_api.call_delay_time(delay or 0, fn)
      return
    end
    fn()
  end

  function defaults.resolve_camera_helper()
    local ctx = runtime_context.current()
    if ctx and type(ctx.camera_helper) == "table" then
      return ctx.camera_helper
    end
    return nil
  end

  function defaults.emit_event(event_name, payload, _opts)
    if type(TriggerCustomEvent) ~= "function" then
      return false
    end
    local ok = pcall(TriggerCustomEvent, event_name, payload or {})
    return ok == true
  end

  -- game_end 单签名直调(ADR 0046):整局结束、全员退出进结算;宿主要求先标记
  -- 各玩家胜负再调用,顺序反了胜负不生效。调用方负责时序,本实现只留痕。
  -- pcall 隔离宿主异常:炸穿会沿事件回调冒泡并跳过后续收尾,异常必须留痕。
  -- 成功判定偏离「明确返回值」标准:返回值真机未取证,暂以「无异常即成功」
  -- 为暂定契约(ADR 0065 已登记例外),取证后按结果收紧。
  function defaults.end_game()
    local game_api = host_context.current_api(runtime_context, game_api_key)
    if game_api == nil or type(game_api.game_end) ~= "function" then
      logger.warn("end_game skip: game api or game_end missing")
      return false
    end
    local ok, err = pcall(game_api.game_end)
    if not ok then
      logger.warn("end_game failed: host game_end raised:", err)
      return false
    end
    return true
  end

  function defaults.is_effect_idle()
    local ok, effect_track = pcall(require, "src.ui.render.support.effect_track")
    if ok and type(effect_track) == "table" and type(effect_track.is_idle) == "function" then
      return effect_track.is_idle()
    end
    return true
  end

  return defaults
end

return default_ports

