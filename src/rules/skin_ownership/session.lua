-- 皮肤归属的本局状态与归属/穿戴写路径(#204 皮肤归属内部)。本局状态住
-- root_state.skin_ownership(本模块独占槽位):按角色的已拥有表、当前穿戴与在途
-- 购买。归属不分来源(ADR 0074 第 1 条):购买、礼物、礼包码都走 mark_owned;
-- 写档失败不撤销本局归属与穿戴,只留 warn(第 3 条)。
local logger = require("src.foundation.log")
local achievement_progress = require("src.rules.ports.achievement_progress")
local archive = require("src.rules.skin_ownership.archive")
local catalog = require("src.rules.skin_ownership.catalog")
local model = require("src.rules.skin_ownership.model")

local session = {}

local SLOT = "skin_ownership"

function session.role_key(role_id)
  if role_id == nil then
    return nil
  end
  return tostring(role_id)
end

-- 只读取,不创建(纯查询用)。
function session.peek(root_state)
  if type(root_state) ~= "table" then
    return nil
  end
  return root_state[SLOT]
end

function session.ensure(root_state)
  if type(root_state) ~= "table" then
    return nil
  end
  root_state[SLOT] = root_state[SLOT] or {
    owned_by_role = {},
    equipped_by_role = {},
    pending_by_role = {},
  }
  return root_state[SLOT]
end

function session.accepted(fields)
  local result = fields or {}
  result.accepted = true
  return result
end

function session.rejected(reason, fields)
  local result = fields or {}
  result.accepted = false
  result.reason = reason
  return result
end

function session.owns(root_state, role_id, product_id)
  local slot = session.peek(root_state)
  local key = session.role_key(role_id)
  local bucket = slot and key and slot.owned_by_role[key] or nil
  return bucket ~= nil and bucket[product_id] == true
end

function session.equipped(root_state, role_id)
  local slot = session.peek(root_state)
  local key = session.role_key(role_id)
  if slot == nil or key == nil then
    return nil
  end
  return slot.equipped_by_role[key]
end

local function _owned_bucket(slot, key)
  slot.owned_by_role[key] = slot.owned_by_role[key] or {}
  return slot.owned_by_role[key]
end

-- 返回写档是否落下;没落下只留 warn,等下次打开皮肤商店补写。
local function _persist_owned(role_id, product_id)
  if archive.mark_owned(role_id, product_id) then
    return true
  end
  logger.warn(
    "skin_ownership: skin ownership archive write failed",
    "role_id=" .. tostring(role_id),
    "product_id=" .. tostring(product_id)
  )
  return false
end

local function _persist_equipped(role_id, product_id)
  if archive.save_equipped(role_id, product_id) then
    return
  end
  logger.warn(
    "skin_ownership: equipped skin archive write failed",
    "role_id=" .. tostring(role_id),
    "product_id=" .. tostring(product_id)
  )
end

-- 返回 (是否记入本局, 是否落档)。
function session.mark_owned(slot, role_id, product_id)
  local key = session.role_key(role_id)
  if key == nil then
    return false, false
  end
  _owned_bucket(slot, key)[product_id] = true
  return true, _persist_owned(role_id, product_id)
end

-- 换模型抛错只留 warn 并按没换成处理,不打断穿戴记账、写档与完成回调。
local function _apply_model(op, ...)
  local ok, applied = pcall(model[op], ...)
  if not ok then
    logger.warn("skin_ownership: model " .. op .. " failed", "role_id=" .. tostring((...)), tostring(applied))
    return false
  end
  return applied
end

-- 穿上:换模型、记本局穿戴、写穿戴存档;模型换成才上报成就进度。返回模型是否换成。
function session.wear(slot, role_id, skin)
  local applied = _apply_model("equip", role_id, skin.product_id)
  if applied then
    achievement_progress.skin_equipped(nil, role_id, skin)
  end
  slot.equipped_by_role[session.role_key(role_id)] = skin.product_id
  _persist_equipped(role_id, skin.product_id)
  return applied
end

function session.take_off(slot, role_id)
  slot.equipped_by_role[session.role_key(role_id)] = nil
  _persist_equipped(role_id, nil)
  _apply_model("unequip", role_id)
end

-- 读档并入本局归属,返回存档归属表;存档读不到时返回 nil。
function session.load_owned(slot, role_id)
  local archived = archive.load_owned(role_id)
  if archived == nil then
    return nil
  end
  local bucket = _owned_bucket(slot, session.role_key(role_id))
  for product_id in pairs(archived) do
    bucket[product_id] = true
  end
  return archived
end

-- ADR 0074 第 3 条:把本局有而存档没有的归属幂等补写。
function session.backfill(slot, role_id, archived)
  for product_id in pairs(_owned_bucket(slot, session.role_key(role_id))) do
    if archived[product_id] ~= true then
      _persist_owned(role_id, product_id)
    end
  end
end

-- 本局尚未穿戴时,按存档穿回已拥有的皮肤;返回穿回的 product_id。
function session.seed_equipped(slot, role_id)
  if slot.equipped_by_role[session.role_key(role_id)] ~= nil then
    return nil
  end
  local product_id = archive.load_equipped(role_id)
  local skin = catalog.skin_by_product(product_id)
  if skin == nil or _owned_bucket(slot, session.role_key(role_id))[product_id] ~= true then
    return nil
  end
  session.wear(slot, role_id, skin)
  return product_id
end

return session
