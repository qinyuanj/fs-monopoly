-- 皮肤归属的存档布局(#193 / #198 / #204 / ADR 0074 / 0075):跨局真源是宿主自定义
-- 玩家存档,经 runtime_ports 读写,不直调宿主。
--   每款皮肤一个 Int archive_key(1 已拥有 / 0 未拥有);
--   穿戴 Int key 存 product_id(0 为未穿);
--   礼包码兑换记录是一个 Str key,存已兑换码 id 的逗号分隔列表。
-- 宿主写档无成功返回值约定,写后回读比对才算落档(ADR 0046 / CODING_STANDARDS 宿主调用)。
local runtime_ports = require("src.foundation.ports.runtime_ports")
local number_utils = require("src.foundation.number")
local logger = require("src.foundation.log")
local skins = require("src.config.content.skins")
local gift_codes = require("src.config.content.gift_codes")
local catalog = require("src.rules.skin_ownership.catalog")

local archive = {}

local OWNED = 1
local NOT_EQUIPPED = 0

local function _archive_key(product_id)
  local skin = catalog.skin_by_product(product_id)
  return skin and skin.archive_key or nil
end

local function _write_int(role_id, key, value)
  if runtime_ports.set_archive_int(role_id, key, value) ~= true then
    return false
  end
  return runtime_ports.get_archive_int(role_id, key) == value
end

function archive.enabled()
  return runtime_ports.archives_enabled() == true
end

-- ADR 0074「不可用不卖」:存档未开启或该款未配 archive_key 都算不可用。
function archive.can_persist(product_id)
  return archive.enabled() and _archive_key(product_id) ~= nil
end

function archive.mark_owned(role_id, product_id)
  if not archive.can_persist(product_id) then
    return false
  end
  return _write_int(role_id, _archive_key(product_id), OWNED)
end

-- 返回存档里的归属表 { [product_id] = true };存档未开启时返回 nil。
function archive.load_owned(role_id)
  if not archive.enabled() then
    logger.warn("skin_ownership: archives disabled, skip reading skin ownership", "role_id=" .. tostring(role_id))
    return nil
  end
  local owned = {}
  for _, skin in ipairs(skins) do
    if skin.archive_key ~= nil and runtime_ports.get_archive_int(role_id, skin.archive_key) == OWNED then
      owned[skin.product_id] = true
    end
  end
  return owned
end

function archive.load_equipped(role_id)
  if not archive.enabled() then
    return nil
  end
  local product_id = runtime_ports.get_archive_int(role_id, skins.equipped_archive_key)
  if product_id == NOT_EQUIPPED then
    return nil
  end
  return product_id
end

function archive.save_equipped(role_id, product_id)
  if not archive.enabled() then
    return false
  end
  return _write_int(role_id, skins.equipped_archive_key, product_id or NOT_EQUIPPED)
end

-- 兑换记录原文;读不到(降级为 nil)与「从未写过」的空串区分,调用方据此拒绝而不覆盖。
function archive.read_redeem_record(role_id)
  local text = runtime_ports.get_archive_str(role_id, gift_codes.redeem_record_archive_key)
  if type(text) ~= "string" then
    return nil
  end
  return text
end

-- 记录里是否已有该码 id;非整数片段跳过。
function archive.record_contains(record_text, id)
  for token in string.gmatch(record_text, "[^,]+") do
    if number_utils.to_integer(token) == id then
      return true
    end
  end
  return false
end

-- 在既有记录后追加码 id 并回读核对;返回是否落档。
function archive.append_redeem_record(role_id, record_text, id)
  local text = record_text == "" and tostring(id) or (record_text .. "," .. tostring(id))
  local key = gift_codes.redeem_record_archive_key
  if runtime_ports.set_archive_str(role_id, key, text) ~= true then
    return false
  end
  return runtime_ports.get_archive_str(role_id, key) == text
end

return archive
