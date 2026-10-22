-- 礼包码兑换 port(#199 / ADR 0075):纯接口壳,不 require 上层实现。兑换门面住
-- app 层(src.app.gift_code.redeem),由 app 组合根(host_install)经 configure 注入;
-- 礼包码屏只经本 port 调用。未注入时 redeem 返回 nil 并留 warn(真机可诊断)。
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

-- 返回门面的结构化结果 { status, granted, message };未注入时返回 nil。
function gift_code_port.redeem(state, role_id, input_text)
  if _impl == nil then
    logger.warn("gift_code port not installed, redeem skipped:", tostring(role_id))
    return nil
  end
  return _impl.redeem(state, role_id, input_text)
end

return gift_code_port
