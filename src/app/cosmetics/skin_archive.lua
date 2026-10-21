-- 皮肤存档适配器(#193 / ADR 0074):皮肤归属与当前穿戴的跨局真源是宿主自定义
-- 玩家存档(Int),经 runtime_ports 读写,不直调宿主。每款皮肤一个 archive_key
-- (1 已拥有 / 0 未拥有),穿戴 key 存 product_id(0 为未穿)。
-- 宿主写档无成功返回值约定,写后回读比对才算落档(CODING_STANDARDS 宿主调用)。
local runtime_ports = require("src.foundation.ports.runtime_ports")
local read_model = require("src.app.cosmetics.transaction_read_model")
local transaction_context = require("src.app.cosmetics.transaction_context")
local skins = require("src.config.content.skins")
local logger = require("src.foundation.log")

local skin_archive = {}

local OWNED = 1
local NOT_EQUIPPED = 0

local function _archive_key(product_id)
  local skin = read_model.skin_by_product(product_id)
  return skin and skin.archive_key or nil
end

local function _write_int(role_id, key, value)
  if runtime_ports.set_archive_int(role_id, key, value) ~= true then
    return false
  end
  return runtime_ports.get_archive_int(role_id, key) == value
end

function skin_archive.can_persist(_, product_id)
  return runtime_ports.archives_enabled() == true and _archive_key(product_id) ~= nil
end

function skin_archive.mark_owned(role_id, product_id)
  if not skin_archive.can_persist(role_id, product_id) then
    return false
  end
  return _write_int(role_id, _archive_key(product_id), OWNED)
end

function skin_archive.load_owned(role_id)
  if runtime_ports.archives_enabled() ~= true then
    logger.warn("skin_archive: archives disabled, skip reading skin ownership", "role_id=" .. tostring(role_id))
    return nil
  end
  local owned = {}
  for _, skin in ipairs(transaction_context.catalog()) do
    if skin.archive_key ~= nil and runtime_ports.get_archive_int(role_id, skin.archive_key) == OWNED then
      owned[skin.product_id] = true
    end
  end
  return owned
end

function skin_archive.load_equipped(role_id)
  if runtime_ports.archives_enabled() ~= true then
    return nil
  end
  local product_id = runtime_ports.get_archive_int(role_id, skins.equipped_archive_key)
  if product_id == NOT_EQUIPPED then
    return nil
  end
  return product_id
end

function skin_archive.save_equipped(role_id, product_id)
  if runtime_ports.archives_enabled() ~= true then
    return false
  end
  return _write_int(role_id, skins.equipped_archive_key, product_id or NOT_EQUIPPED)
end

return skin_archive
