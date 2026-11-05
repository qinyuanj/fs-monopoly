-- 礼包码兑换 port(#199 / #204 / #224 / ADR 0075):纯接口壳,不 require 规则层实现。
-- 兑换与入口查询住皮肤归属模块(src.rules.skin_ownership),由 app 组合根(host_install)
-- 经 configure 注入,测试注入假实现;礼包码屏只经本 port 调用。未注入时 redeem 返回
-- nil、owns_all_rewards 返回 false(入口照常显示),都留 warn(真机可诊断)。
local logger = require("src.foundation.log")

local gift_code_port = {}

local _impl = nil

function gift_code_port.configure(impl)
  assert(type(impl) == "table" and type(impl.redeem) == "function",
    "gift_code_port.configure: impl.redeem must be a function")
  _impl = impl
end

function gift_code_port.reset_for_tests()
  _impl = nil
end

function gift_code_port.is_configured()
  return _impl ~= nil
end

-- 返回结构化结果 { status, granted };未注入时返回 nil。
function gift_code_port.redeem(state, role_id, input_text)
  if _impl == nil then
    logger.warn("gift_code port not installed, redeem skipped:", tostring(role_id))
    return nil
  end
  return _impl.redeem(state, role_id, input_text)
end

-- #224:玩家是否已拥有所有在用礼包码的全部奖励;未注入(或注入的实现不带此查询)时
-- 按 false 处理,入口照常显示。
function gift_code_port.owns_all_rewards(state, role_id)
  if _impl == nil or type(_impl.owns_all_rewards) ~= "function" then
    logger.warn("gift_code port not installed, entry query treated as not owned:", tostring(role_id))
    return false
  end
  return _impl.owns_all_rewards(state, role_id) == true
end

return gift_code_port
