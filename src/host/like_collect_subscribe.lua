local logger = require("src.foundation.log")

local like_collect_subscribe = {}

-- 事件名以编辑器配置为真源；与 view_command 的 SHARE_TASK_OPEN_EVENT 同一约定：
-- 编辑器侧配同名监听触发器，Lua 侧逐字不可漂移。
-- 命名职责单一（参考伪人检查站守卫蛋仔岛 Person.lua 的入口/进度事件名隔离）：
-- evt_not_subscribe = 订阅入口点击的 UI 自定义事件；evt_subscribe = 进图已订阅时
-- 回发的任务进度单位事件（progress_source 同名，宿主任务系统累计）。
local LIKE_EVENT = "evt_click_like"
local COLLECT_EVENT = "evt_add_collection"
local SUBSCRIBE_EVENT = "evt_subscribe"
local SUBSCRIBE_CLICK_EVENT = "evt_not_subscribe"

local SUBSCRIBE_TIPS_TEXT = "点击\"更多\"完成订阅，下次登录领取订阅任务奖励。"
local SUBSCRIBE_TIPS_DURATION = 3.0
local MAP_ENTER_CHECK_DELAY = 0.1

local runtime_field = "__like_collect_subscribe_runtime"

local function _new_runtime()
  return {
    setup_done = false,
    subscribe_sent = false,
  }
end

local function _runtime(game)
  local rt = game[runtime_field]
  if not rt then
    rt = _new_runtime()
    game[runtime_field] = rt
  end
  return rt
end

local function _trigger_ready()
  return RegisterTriggerEvent ~= nil and EVENT ~= nil and EVENT.UI_CUSTOM_EVENT ~= nil
end

local function _role_from_data(data)
  return data and data.role or nil
end

local function _get_ctrl_unit(role)
  if role == nil or type(role.get_ctrl_unit) ~= "function" then
    return nil
  end
  local ok, unit = pcall(role.get_ctrl_unit)
  if not ok or unit == nil then
    return nil
  end
  return unit
end

local function _send_unit_event(role, event_name)
  local unit = _get_ctrl_unit(role)
  if unit == nil then
    logger.warn("like_collect_subscribe unit missing:", event_name)
    return false
  end
  if LuaAPI == nil or type(LuaAPI.unit_send_custom_event) ~= "function" then
    logger.warn("like_collect_subscribe LuaAPI missing:", event_name)
    return false
  end
  local ok, err = pcall(LuaAPI.unit_send_custom_event, unit, event_name, {})
  if not ok then
    logger.warn("like_collect_subscribe send failed:", event_name, tostring(err))
    return false
  end
  return true
end

local function _show_like_panel(role, event_name)
  if role == nil or type(role.show_like_panel) ~= "function" then
    logger.warn("like_collect_subscribe show_like_panel missing:", event_name)
    return
  end
  local ok, err = pcall(role.show_like_panel)
  if not ok then
    logger.warn("like_collect_subscribe show_like_panel failed:", event_name, tostring(err))
  end
end

local function _handle_like_or_collect(event_name, data)
  local role = _role_from_data(data)
  _show_like_panel(role, event_name)
  if role ~= nil then
    _send_unit_event(role, event_name)
  end
end

local function _show_tips(text, duration)
  if GlobalAPI == nil or type(GlobalAPI.show_tips) ~= "function" then
    logger.warn("like_collect_subscribe GlobalAPI.show_tips missing")
    return
  end
  local ok, err = pcall(GlobalAPI.show_tips, text, duration)
  if not ok then
    logger.warn("like_collect_subscribe show_tips failed:", tostring(err))
  end
end

local function _handle_subscribe_click(data)
  local role = _role_from_data(data)
  _show_like_panel(role, SUBSCRIBE_CLICK_EVENT)
  _show_tips(SUBSCRIBE_TIPS_TEXT, SUBSCRIBE_TIPS_DURATION)
end

local function _all_valid_roles()
  if GameAPI == nil or type(GameAPI.get_all_valid_roles) ~= "function" then
    return nil
  end
  local ok, roles = pcall(GameAPI.get_all_valid_roles)
  if not ok or type(roles) ~= "table" then
    return nil
  end
  return roles
end

local function _first_valid_role()
  local roles = _all_valid_roles()
  if roles == nil or #roles == 0 then
    return nil
  end
  return roles[1]
end

-- 进图订阅状态：已订阅返回进度事件名 evt_subscribe；未订阅返回 nil——
-- 未订阅不发任何事件（与参考实现一致，evt_not_subscribe 只作入口点击事件名）。
local function _subscription_event_name(role)
  if type(role.is_subscribed_map_author) ~= "function" then
    logger.warn("like_collect_subscribe is_subscribed_map_author missing")
    return nil
  end
  local ok, subscribed = pcall(role.is_subscribed_map_author)
  if not ok then
    logger.warn("like_collect_subscribe subscription check failed:", tostring(subscribed))
    return nil
  end
  if not subscribed then
    return nil
  end
  return SUBSCRIBE_EVENT
end

local function _check_subscription(game)
  local rt = _runtime(game)
  if rt.subscribe_sent then
    return
  end
  local role = _first_valid_role()
  if role == nil then
    logger.warn("like_collect_subscribe no valid role for subscription check")
    return
  end
  local event_name = _subscription_event_name(role)
  if event_name == nil then
    return
  end
  -- 只锁存成功发送：瞬时失败（unit 缺失/宿主抛错）不吞掉，下次检测可重试。
  if _send_unit_event(role, event_name) then
    rt.subscribe_sent = true
  end
end

local function _register_listener(event_name, callback)
  RegisterTriggerEvent({ EVENT.UI_CUSTOM_EVENT, event_name }, callback)
end

function like_collect_subscribe.setup(game)
  local rt = _runtime(game)
  if rt.setup_done then
    return
  end
  if not _trigger_ready() then
    logger.warn("like_collect_subscribe host event contract missing")
    return
  end

  _register_listener(LIKE_EVENT, function(_, _, data)
    _handle_like_or_collect(LIKE_EVENT, data or {})
  end)
  _register_listener(COLLECT_EVENT, function(_, _, data)
    _handle_like_or_collect(COLLECT_EVENT, data or {})
  end)
  _register_listener(SUBSCRIBE_CLICK_EVENT, function(_, _, data)
    _handle_subscribe_click(data or {})
  end)

  if type(SetTimeOut) == "function" then
    local ok, err = pcall(SetTimeOut, MAP_ENTER_CHECK_DELAY, function()
      _check_subscription(game)
    end)
    if not ok then
      logger.warn("like_collect_subscribe schedule check failed:", tostring(err))
    end
  else
    logger.warn("like_collect_subscribe SetTimeOut missing")
  end

  rt.setup_done = true
end

-- Test seam exports
like_collect_subscribe._runtime = _runtime
like_collect_subscribe._handle_like_or_collect = _handle_like_or_collect
like_collect_subscribe._handle_subscribe_click = _handle_subscribe_click
like_collect_subscribe._check_subscription = _check_subscription

return like_collect_subscribe

