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

