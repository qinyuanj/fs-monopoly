-- 皮肤归属(#204 / ADR 0074 / 0075):玩家已拥有某款皮肤的事实及其全部规则——拥有、
-- 穿戴、本局缓存、付费购买结算、礼物解锁、礼包码兑换与换模型。
-- 对外只有下列命令与查询,均以 root_state 为首参;本局状态住 root_state.skin_ownership。
-- 宿主交互只经现有 seam:玩家存档、墙钟、角色换模型经 runtime_ports,付费经付费
-- 购买 port,换装成就经成就进度 port。返回值只含领域字段(accepted / reason /
-- product_id / equipped / persisted / status / granted),文案与关屏归屏。
local catalog = require("src.rules.skin_ownership.catalog")
local session = require("src.rules.skin_ownership.session")
local purchase = require("src.rules.skin_ownership.purchase")
local redeem = require("src.rules.skin_ownership.redeem")

local skin_ownership = {}

local function _slot_for_command(root_state, role_id)
  local slot = session.ensure(root_state)
  if slot == nil then
    return nil, session.rejected("missing_state")
  end
  if role_id == nil then
    return nil, session.rejected("missing_role")
  end
  return slot, nil
end

-- ADR 0074 第 4 条:开局读档并恢复穿戴,不补写。返回穿回的 product_id。
function skin_ownership.restore(root_state, role_id)
  local slot = _slot_for_command(root_state, role_id)
  if slot == nil then
    return nil
  end
  session.load_owned(slot, role_id)
  return session.seed_equipped(slot, role_id)
end

-- ADR 0074 第 3、4 条:打开皮肤商店时再读一次档,并把本局有而存档没有的归属幂等
-- 补写;存档读不到时不补写。返回穿回的 product_id。
function skin_ownership.sync_on_shop_open(root_state, role_id)
  local slot = _slot_for_command(root_state, role_id)
  if slot == nil then
    return nil
  end
  local archived = session.load_owned(slot, role_id)
  if archived ~= nil then
    session.backfill(slot, role_id, archived)
  end
  return session.seed_equipped(slot, role_id)
end

-- 纯查询:不创建任何状态。
skin_ownership.owns = session.owns
skin_ownership.equipped = session.equipped

-- 穿上已拥有的皮肤;equipped 为模型是否换成(换不成仍记本局穿戴并写档)。
function skin_ownership.equip(root_state, role_id, product_id)
  local skin = catalog.skin_by_product(product_id)
  if skin == nil then
    return session.rejected("missing_product", { product_id = product_id })
  end
  local slot, rejected = _slot_for_command(root_state, role_id)
  if slot == nil then
    return rejected
  end
  if not session.owns(root_state, role_id, product_id) then
    return session.rejected("not_owned", { product_id = product_id })
  end
  return session.accepted({ product_id = product_id, equipped = session.wear(slot, role_id, skin) })
end

function skin_ownership.unequip(root_state, role_id)
  local slot, rejected = _slot_for_command(root_state, role_id)
  if slot == nil then
    return rejected
  end
  session.take_off(slot, role_id)
  return session.accepted({})
end

-- 发起付费购买;宿主回调完成时调用 on_complete(result),result 含
-- accepted / reason / product_id / equipped / persisted。
skin_ownership.start_purchase = purchase.start

-- 非购买来源的解锁(礼物),与购买走同一归属写档路径;persisted 回报是否落档。
function skin_ownership.grant(root_state, role_id, product_id)
  if catalog.skin_by_product(product_id) == nil then
    return session.rejected("missing_product", { product_id = product_id })
  end
  local slot, rejected = _slot_for_command(root_state, role_id)
  if slot == nil then
    return rejected
  end
  local _, persisted = session.mark_owned(slot, role_id, product_id)
  return session.accepted({ product_id = product_id, persisted = persisted })
end

-- 礼包码兑换,返回 { status, granted }。
skin_ownership.redeem = redeem.redeem

-- 按价格升序、同价按 order、再按源下标稳定排序的皮肤目录(#495 裁定)。
skin_ownership.catalog = catalog.sorted

return skin_ownership
