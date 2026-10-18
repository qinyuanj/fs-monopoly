local paid_goods_cfg = require("src.rules.commerce.paid_goods")

local bridge = {}

local function _currency_key(currency)
  return currency and tostring(currency) or nil
end

local function _currency_entry(currency)
  if paid_goods_cfg.enabled ~= true then
    return nil
  end
  local key = _currency_key(currency)
  if not key then
    return nil
  end
  local currencies = paid_goods_cfg.currencies or {}
  return currencies[key]
end

-- 行为测试公共查询：test_paid_currency 区分宿主管理的 commodity 与外部付费货币，
-- 并通过真实商品购买流程验证外部货币仍可唤起购买面板。
function bridge.is_managed_currency(_, currency)
  local entry = _currency_entry(currency)
  if not entry then
    return false
  end
  return entry.source == "commodity"
end

function bridge.is_paid_currency(currency)
  return _currency_entry(currency) ~= nil
end

function bridge.setup_for_game(_)
  return true
end

return bridge

--[[ mutate4lua-manifest
version=4
projectHash=1160c6e009f1e6d4
scope.0.id=chunk:src/rules/commerce/paid_currency_bridge.lua
scope.0.kind=chunk
scope.0.startLine=1
scope.0.endLine=42
scope.0.semanticHash=cc3b3cd00ccfb1c4
scope.1.id=function:_currency_entry
scope.1.kind=function
scope.1.startLine=5
scope.1.endLine=15
scope.1.semanticHash=8f89f17f2d39d7f6
scope.2.id=function:bridge.is_managed_currency
scope.2.kind=function
scope.2.startLine=17
scope.2.endLine=23
scope.2.semanticHash=1379e5cead520ee6
scope.3.id=function:bridge.is_paid_currency
scope.3.kind=function
scope.3.startLine=25
scope.3.endLine=27
scope.3.semanticHash=41ca328ef191d311
scope.4.id=function:bridge.is_currency_channel_ready
scope.4.kind=function
scope.4.startLine=29
scope.4.endLine=31
scope.4.semanticHash=c54eae7d0a1663a6
scope.5.id=function:bridge.unavailable_reason
scope.5.kind=function
scope.5.startLine=33
scope.5.endLine=35
scope.5.semanticHash=31c71a80afd9d8b5
scope.6.id=function:bridge.setup_for_game
scope.6.kind=function
scope.6.startLine=37
scope.6.endLine=39
scope.6.semanticHash=b25a3b7ccdeba99d
]]
