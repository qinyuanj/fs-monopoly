-- 宿主出局调用的规则层触达点(ADR 0046):方法在 Role 还是控制单位上、调用签名
-- 与成功判据(#610 取证:宿主经 unit.is_die_status 回读,合成适配器按 truthy)
-- 全部收在 src/host/role_die,本模块只经 runtime_ports 转发,规则层对宿主对象
-- 与组件系统零知识,成功判据只看端口返回 true。
local runtime_ports = require("src.foundation.ports.runtime_ports")

local life_loss = {}

function life_loss.try_call_life_die(role)
  if not role then
    return false
  end
  return runtime_ports.call_role_die(role) == true
end

return life_loss

