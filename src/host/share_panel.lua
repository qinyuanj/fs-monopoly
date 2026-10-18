local logger = require("src.foundation.log")
local role_id_utils = require("src.foundation.identity")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local host_types = require("src.foundation.host_types")

local share_panel = {}

-- 「宿主分享面板」触发口的宿主实现（#463 自 foundation/ports 下沉，契约 port 与
-- 装配接线见 src/foundation/ports/share_panel.lua 与 host_install）：Lua 只负责
-- 唤起，面板内容、生命周期与分享结果归宿主。tag 区分调用方日志前缀（托管首点
-- 沿用历史钉住的 "auto share panel"）。
local function _invoke_show_panel(show_map_share_panel, tag)
  -- 不用 host_types.call：成功判定依赖「不抛错」而非返回值，见 call 的 nil 聚合
  -- 注释——调用不抛错（含返回 nil）即视为面板已唤起。
  local ok, err = pcall(show_map_share_panel)
  if not ok then
    logger.warn(tag .. " raised:", tostring(err))
    return false
  end
  return true
end

function share_panel.try_show(actor_role_id, tag)
  tag = tag or "share panel"
  local role_id = role_id_utils.normalize(actor_role_id)
  local role = role_id and runtime_ports.resolve_role(role_id) or nil
  -- 只验方法存在：宿主 Role 是 userdata（CampRole），type() 返回自定义类型名，
  -- 用 type(role) ~= "table" 会把合法宿主 Role 误判缺失。nil 守卫、索引 pcall
  -- 与函数类型检查全部收敛进 host_types.method，取不到统一返回 nil。
  local show_map_share_panel = host_types.method(role, "show_map_share_panel")
  if show_map_share_panel == nil then
    logger.warn(tag .. " skipped: role or show_map_share_panel missing:", tostring(role_id))
    return false
  end
  return _invoke_show_panel(show_map_share_panel, tag)
end

return share_panel

