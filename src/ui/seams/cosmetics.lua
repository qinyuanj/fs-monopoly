-- cosmetics port:纯接口壳,不 require 上层实现(工单 #244 拆除 ui→app 上行依赖)。
-- transaction / transaction_state 实现由 app 组合根(compose_game,ADR 0001)经
-- install 注入;build 返回稳定转发代理,消费方可在装配前 require,真正取用未注入的
-- 实现字段时才断言失败。
local cosmetics_port = {}

local _impl = nil
local _pending = {}

local function _resolve(field)
  local impl = assert(_impl, "cosmetics port not installed: " .. field)
  return assert(impl[field], "cosmetics port impl missing field: " .. field)
end

local function _forwarding_proxy(field)
  return setmetatable({}, {
    __index = function(_, key)
      return _resolve(field)[key]
    end,
  })
end

local _port = {
  transaction = _forwarding_proxy("transaction"),
  transaction_state = _forwarding_proxy("transaction_state"),
}

function cosmetics_port.install(impl)
  assert(type(impl) == "table", "cosmetics_port.install: impl must be a table")
  _impl = impl
  local pending = _pending
  _pending = {}
  for _, callback in ipairs(pending) do
    callback(_port)
  end
  return _port
end

-- 注入完成后执行(已注入则立即执行):消费方模块加载期的初始化副作用挂这里,
-- 避免 require 顺序反向耦合装配顺序。
function cosmetics_port.when_installed(callback)
  if _impl ~= nil then
    callback(_port)
    return
  end
  _pending[#_pending + 1] = callback
end

function cosmetics_port.build()
  return _port
end

return cosmetics_port

