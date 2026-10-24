-- 皮肤归属 ui seam(#204,取代 seams/cosmetics):纯接口壳,不 require 规则层实现
-- (ui_no_rules)。皮肤商店屏只经这里看到皮肤归属的窄接口;实现由 app 组合根
-- (compose_game)经 install 注入——生产装配注入规则层皮肤归属模块,屏测试注入
-- 假实现。调用时才取实现,消费方可在装配前 require。
local skin_ownership_seam = {}

local OPERATIONS = {
  "catalog",
  "owns",
  "equipped",
  "sync_on_shop_open",
  "equip",
  "unequip",
  "start_purchase",
  "grant",
}

local _impl = nil

function skin_ownership_seam.install(impl)
  assert(type(impl) == "table", "skin_ownership seam: impl must be a table")
  for _, name in ipairs(OPERATIONS) do
    assert(type(impl[name]) == "function", "skin_ownership seam: impl missing " .. name)
  end
  _impl = impl
end

-- 当前注入的实现;测试换假实现前取出,收尾装回。
function skin_ownership_seam.current()
  return _impl
end

for _, name in ipairs(OPERATIONS) do
  skin_ownership_seam[name] = function(...)
    return assert(_impl, "skin_ownership seam not installed: " .. name)[name](...)
  end
end

return skin_ownership_seam
