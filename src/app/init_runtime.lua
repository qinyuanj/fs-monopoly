local logger = require("src.foundation.log")
local host_types = require("src.foundation.host_types")
local runtime_ports = require("src.foundation.ports.runtime_ports")

local init_runtime = {}

local _GAME_TIME_METHODS = { "get_timestamp", "get_hour", "get_minute", "get_second" }

-- GameAPI / GlobalAPI 是宿主注入的对象，type() 未必是 "table"（#266），一律
-- 鸭子判定：要用的方法取得到就算有。
function init_runtime.has_game_time_api(game_api)
  if game_api == nil then return false end
  if type(logger.configure_game_time) ~= "function" then return false end
  for _, name in ipairs(_GAME_TIME_METHODS) do
    if host_types.method(game_api, name) == nil then return false end
  end
  return true
end

function init_runtime.configure_game_time_logger(game_api)
  if init_runtime.has_game_time_api(game_api) then
    logger.configure_game_time(game_api)
    return
  end
  if type(logger.reset_time_runtime) == "function" then
    logger.reset_time_runtime()
  end
end

local function _has_enabled_debug_role(enabled_by_role)
  for _, enabled in pairs(enabled_by_role or {}) do
    if enabled == true then
      return true
    end
  end
  return false
end

-- 取 state 上的 anim_debug 按角色开关表:state 或其字段缺省时统一 nil,
-- 与下方 provider 的「非表即 false」语义衔接。
local function _enabled_debug_role(state)
  local ui = state and state.ui or nil
  return ui and ui.anim_debug_enabled_by_role or nil
end

function init_runtime.build_anim_debug_provider(state)
  return function()
    local enabled_by_role = _enabled_debug_role(state)
    if type(enabled_by_role) ~= "table" then
      return false
    end
    return _has_enabled_debug_role(enabled_by_role)
  end
end

local function _show_warn_in_ui(text)
  local marquee = host_types.method(GlobalAPI, "show_message_marquee")
  if marquee ~= nil then
    pcall(marquee, text)
    return
  end
  local show_tips = host_types.method(GlobalAPI, "show_tips")
  if show_tips ~= nil then
    pcall(show_tips, text, 3.0)
  end
end

-- #522(ADR 0030「嫌吵加过滤、不砍通道」的过滤决策):warn 默认只进 log.txt,
-- 只有调用点显式声明(logger.warn_ui → entry.ui == true)的玩家可见提示才
-- 上屏。真机事故原型:终局 AI 面板跳过留痕(ADR 0046)经本 sink 广播成
-- 全员 toast。and 链短路保证 nil entry 不索引字段。
local function _is_ui_routable_warn(entry)
  return entry ~= nil and entry.level == "warn" and entry.ui == true
end

function init_runtime.build_ui_warn_sink()
  return function(entry)
    if not _is_ui_routable_warn(entry) then return end
    if GlobalAPI == nil then return end
    _show_warn_in_ui("[warn] " .. tostring(entry.text or ""))
  end
end

-- 私人提示（tip.role_id 非空，如道具槽拒绝）只投给该玩家：广播出去既是信息泄露
-- 也是噪音。role 解析不出或宿主没有 Role.show_tips 时返回 false，由调用方回落广播。
--
-- 不要用 type(role) == "table" 把门：Eggy 沙盒的 type() 对宿主对象返回的是宿主
-- 类名（真机取证 #266：Role 返回 "CampRole"），这道门会恒假地把每条私人提示都
-- 打回广播——功能不崩、外观与改前完全一致，是最难发现的失败模式。宿主对象一律
-- 鸭子判定：能取到要用的那个方法就用。
local function _tip_role_id(tip)
  return tip and tip.role_id or nil
end

-- role 可能是任意宿主类型，索引本身也可能抛；nil 守卫、索引 pcall、函数类型
-- 检查全部收敛进 host_types.method，取不到统一返回 nil。
local function _show_tips_of(role)
  return host_types.method(role, "show_tips")
end

-- 不用 host_types.call：投递判定依赖「不抛错」而非返回值，见 call 的 nil 聚合
-- 注释——调用不抛错（含返回 nil）即视为已投递，仅宿主明确返回 false 或调用
-- 抛错时才回落广播。
local function _call_show_tips(show_tips, text, duration)
  local ok, shown = pcall(show_tips, text, duration)
  return ok and shown ~= false
end

function init_runtime.try_show_tip_to_role(tip, text, duration)
  local role_id = _tip_role_id(tip)
  if role_id == nil then
    return false
  end
  local show_tips = _show_tips_of(runtime_ports.resolve_role(role_id))
  if show_tips == nil then
    return false
  end
  return _call_show_tips(show_tips, text, duration)
end

return init_runtime

