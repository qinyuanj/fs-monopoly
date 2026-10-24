-- 皮肤归属 ui seam 的测试假实现(#204):seam 的第二个 adapter。内存里按角色记
-- 归属与穿戴,记录每次命令调用;付费购买不自动完成,测试调 complete_purchase
-- 模拟宿主回调。屏测试经它只验证请求映射与结果展示,不依赖存档细节。
--   opts.catalog            目录(默认空)
--   opts.restored           sync_on_shop_open 的返回(穿回的 product_id)
--   opts.purchase_refusal   start_purchase 拒绝原因(nil 为接受)
require("test.bootstrap").install_package_paths()
local skin_ownership_seam = require("src.ui.seams.skin_ownership")

local M = {}

local function _key(role_id)
  if role_id == nil then
    return nil
  end
  return tostring(role_id)
end

function M.new(opts)
  opts = opts or {}
  local fake = {
    catalog_list = opts.catalog or {},
    restored = opts.restored,
    purchase_refusal = opts.purchase_refusal,
    owned = {},
    worn = {},
    calls = {},
    purchases = {},
  }

  local function _record(op, role_id, product_id)
    fake.calls[#fake.calls + 1] = { op = op, role_id = role_id, product_id = product_id }
  end

  -- 测试直接摆归属/穿戴。
  function fake.own(role_id, product_id)
    local key = _key(role_id)
    fake.owned[key] = fake.owned[key] or {}
    fake.owned[key][product_id] = true
  end

  function fake.wear(role_id, product_id)
    fake.own(role_id, product_id)
    fake.worn[_key(role_id)] = product_id
  end

  function fake.catalog()
    return fake.catalog_list
  end

  function fake.owns(_, role_id, product_id)
    local bucket = fake.owned[_key(role_id) or ""]
    return bucket ~= nil and bucket[product_id] == true
  end

  function fake.equipped(_, role_id)
    return fake.worn[_key(role_id) or ""]
  end

  function fake.sync_on_shop_open(_, role_id)
    _record("sync_on_shop_open", role_id)
    return fake.restored
  end

  function fake.equip(state, role_id, product_id)
    _record("equip", role_id, product_id)
    if role_id == nil then
      return { accepted = false, reason = "missing_role" }
    end
    if not fake.owns(state, role_id, product_id) then
      return { accepted = false, reason = "not_owned", product_id = product_id }
    end
    fake.worn[_key(role_id)] = product_id
    return { accepted = true, product_id = product_id, equipped = true }
  end

  function fake.unequip(_, role_id)
    _record("unequip", role_id)
    if role_id == nil then
      return { accepted = false, reason = "missing_role" }
    end
    fake.worn[_key(role_id)] = nil
    return { accepted = true }
  end

  function fake.grant(_, role_id, product_id)
    _record("grant", role_id, product_id)
    if role_id == nil then
      return { accepted = false, reason = "missing_role" }
    end
    fake.own(role_id, product_id)
    return { accepted = true, product_id = product_id, persisted = true }
  end

  function fake.start_purchase(_, role_id, product_id, on_complete)
    _record("start_purchase", role_id, product_id)
    if fake.purchase_refusal ~= nil then
      return { accepted = false, reason = fake.purchase_refusal, product_id = product_id }
    end
    fake.purchases[#fake.purchases + 1] = { role_id = role_id, product_id = product_id, on_complete = on_complete }
    return { accepted = true, product_id = product_id }
  end

  -- 模拟宿主回调完成最近一笔(或第 index 笔)购买;result 可覆盖完成结果。
  function fake.complete_purchase(index, result)
    local purchase = fake.purchases[index or #fake.purchases]
    if result == nil then
      fake.wear(purchase.role_id, purchase.product_id)
      result = { accepted = true, product_id = purchase.product_id, equipped = true, persisted = true }
    end
    purchase.on_complete(result)
  end

  -- 命令调用序列,形如 "grant:1:skin_2"。
  function fake.ops()
    local ops = {}
    for _, call in ipairs(fake.calls) do
      ops[#ops + 1] = call.op .. ":" .. tostring(call.role_id) .. ":" .. tostring(call.product_id)
    end
    return ops
  end

  return fake
end

-- 装入假实现,返回装回原实现的函数。
function M.install(fake)
  local previous = skin_ownership_seam.current()
  skin_ownership_seam.install(fake)
  return function()
    skin_ownership_seam.install(previous)
  end
end

return M
