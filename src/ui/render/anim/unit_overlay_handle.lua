local host_types = require("src.foundation.host_types")
local logger = require("src.foundation.log")

local handle_ops = {}
local robot_scale = host_types.vec3(0.06, 0.94, 0.06)
local robot_rotation = host_types.quat(0.0, 0.0, 0.0)

local function _access_field(obj, key)
  return obj[key]
end

local function _call_handle_method(handle, method_name, ...)
  if handle == nil then return false end
  local ok, method = pcall(_access_field, handle, method_name)
  if not ok or type(method) ~= "function" then return false end
  local called = pcall(method, ...)
  return called == true
end

function handle_ops.spawn(hr, robot_id, pos)
  -- ADR 0046「跳过必留痕」:nil 路径零告警是 #339 清障机器人盲区之一。
  if robot_id == nil then
    logger.warn("[unit_overlay_handle]", "spawn with nil robot_id")
    return nil
  end
  -- #339:不走 entity_pool 池化,直接 create——池复用(idle_reuse)复用对象的
  -- 可见性恢复在真机不可靠(模型没重显),临时特效直接生成/销毁最简可见。
  if type(hr.create_unit_with_scale) ~= "function" then
    logger.warn("[unit_overlay_handle]", "spawn: no create_unit_with_scale on host runtime")
    return nil
  end
  local handle = hr.create_unit_with_scale(robot_id, pos, robot_rotation, robot_scale)
  if handle == nil then
    logger.warn("[unit_overlay_handle]", "spawn returned nil handle for robot_id="
      .. tostring(robot_id) .. " pos=" .. tostring(pos))
  end
  return handle
end

function handle_ops.destroy(hr, robot_id, handle)
  if handle == nil then
    return
  end
  -- #339:不走池化,直接 destroy(不再 release_unit 回池)。
  if type(hr.destroy_unit) == "function" then
    hr.destroy_unit(handle)
    return
  end
  if type(hr.destroy_unit_with_children) == "function" then
    hr.destroy_unit_with_children(handle, true)
    return
  end
end

function handle_ops.move(hr, robot_id, handle, pos)
  if _call_handle_method(handle, "set_position_smooth", pos) then
    return handle
  end
  if _call_handle_method(handle, "set_position", pos) then
    return handle
  end
  handle_ops.destroy(hr, robot_id, handle)
  return handle_ops.spawn(hr, robot_id, pos)
end

return handle_ops

