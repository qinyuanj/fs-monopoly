-- 工具/平台不可用的退出码与子进程诊断认领。依赖缺失或版本越界由受控
-- Lua 环境预检按真实失败报出;本模块不安装工具、不判定网络错误。
local boundary = require("foundation.platform_boundary")

local availability = {}

availability.EXIT_CODE = boundary.UNAVAILABLE_EXIT_CODE

-- 退 3 与状态词俱在才算不可用,返回原样输出;缺一按真实失败处理。
function availability.child_diagnostic(code, output)
  local text = tostring(output or "")
  if code == availability.EXIT_CODE and text:find("status=" .. boundary.UNAVAILABLE, 1, true) ~= nil then
    return text
  end
  return nil
end

return availability
