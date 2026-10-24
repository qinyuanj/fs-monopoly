-- 礼包码兑换门面(#198 / #203 / ADR 0075)。redeem(state, role_id, input_text) 封装
-- 规范化、按哈希查码(gift_code_catalog)、过期判定、兑换记录读写与奖励发放,返回结构化结果:
--   { status = <下列之一>, granted = { product_id... }, message = <提示文本> }
--   granted / all_owned / invalid_code / expired / already_redeemed /
--   archive_unavailable / write_failed
-- 宿主存档与墙钟经 runtime_ports;奖励经 cosmetics transaction 门面的授予归属入口
-- 写档(ADR 0074 第 1 条,不另开归属真源)。
-- 顺序:存档不可用直接拒绝(不读不写)→ 查码 → 过期 → 读兑换记录 → 发放未拥有
-- 皮肤 → 追加兑换记录并回读核对。记录写档失败不撤销已发归属(ADR 0074 第 3 条),
-- 重试时这些皮肤按已拥有跳过;皮肤归属写档失败则不写记录,留给重试时发放。
local runtime_ports = require("src.foundation.ports.runtime_ports")
local logger = require("src.foundation.log")
local number_utils = require("src.foundation.number")
local gift_codes = require("src.config.content.gift_codes")
local gift_code_catalog = require("src.rules.skin_ownership.gift_code_table")
local redeem_record = require("src.app.gift_code.redeem_record")
local transaction = require("src.app.cosmetics.transaction")
local transaction_state = require("src.app.cosmetics.transaction_state")

local redeem = {}

local catalog = gift_code_catalog.default()

local function _result(status, granted, detail)
  local template = gift_codes.messages[status]
  return {
    status = status,
    granted = granted or {},
    message = detail and string.format(template, detail) or template,
  }
end

local function _warn(message, role_id, entry, extra)
  logger.warn(
    "gift_code: " .. message,
    "role_id=" .. tostring(role_id),
    "code_id=" .. tostring(entry and entry.id),
    extra
  )
end

-- 墙钟取不到(0 / nil)不判过期。
local function _expired(entry)
  if entry.expires_at == nil then
    return false
  end
  local now = runtime_ports.wall_now_seconds()
  if not number_utils.is_numeric(now) or now <= 0 then
    return false
  end
  return now > entry.expires_at
end

local function _write_record(role_id, text)
  local key = gift_codes.redeem_record_archive_key
  if runtime_ports.set_archive_str(role_id, key, text) ~= true then
    return false
  end
  return runtime_ports.get_archive_str(role_id, key) == text
end

-- 皮肤名与发放路径同一份目录(#195 review):grant_ownership 按
-- transaction_state.skin_by_product 解析皮肤,提示不另扫一份静态 skins。
local function _skin_names(product_ids)
  local names = {}
  for _, product_id in ipairs(product_ids) do
    local skin = transaction_state.skin_by_product(product_id)
    if skin ~= nil and skin.name ~= nil then
      names[#names + 1] = skin.name
    end
  end
  return table.concat(names, "、")
end

-- 返回 (本次发放列表, 是否全部落档)。
local function _grant_missing(state, role_id, entry, archived)
  local granted = {}
  local all_persisted = true
  for _, product_id in ipairs(entry.rewards) do
    if archived[product_id] ~= true then
      local result = transaction.grant_ownership(state, role_id, product_id)
      if result.accepted == true then
        granted[#granted + 1] = product_id
      end
      all_persisted = all_persisted and result.persisted == true
    end
  end
  return granted, all_persisted
end

local function _lookup(input_text)
  local entry = catalog.find(input_text)
  if entry == nil then
    return nil, _result("invalid_code")
  end
  if _expired(entry) then
    return nil, _result("expired")
  end
  return entry, nil
end

local function _read_record(role_id, entry)
  local text = runtime_ports.get_archive_str(role_id, gift_codes.redeem_record_archive_key)
  if type(text) ~= "string" then
    _warn("redeem record unreadable", role_id, entry)
    return nil, _result("archive_unavailable")
  end
  if redeem_record.contains(redeem_record.parse(text), entry.id) then
    return nil, _result("already_redeemed")
  end
  return text, nil
end

local function _grant_and_record(state, role_id, entry, record_text)
  local archived = transaction.refresh_ownership(state, role_id)
  if archived == nil then
    _warn("skin ownership unreadable", role_id, entry)
    return _result("archive_unavailable")
  end
  local granted, all_persisted = _grant_missing(state, role_id, entry, archived)
  if not all_persisted then
    _warn("skin ownership write failed, record not written", role_id, entry)
    return _result("write_failed", granted)
  end
  if not _write_record(role_id, redeem_record.append(record_text, entry.id)) then
    _warn("redeem record write failed", role_id, entry, "record=" .. tostring(record_text))
    return _result("write_failed", granted)
  end
  if #granted == 0 then
    return _result("all_owned")
  end
  return _result("granted", granted, _skin_names(granted))
end

function redeem.redeem(state, role_id, input_text)
  if runtime_ports.archives_enabled() ~= true then
    return _result("archive_unavailable")
  end
  local entry, rejected = _lookup(input_text)
  if rejected ~= nil then
    return rejected
  end
  local record_text, record_rejected = _read_record(role_id, entry)
  if record_rejected ~= nil then
    return record_rejected
  end
  return _grant_and_record(state, role_id, entry, record_text)
end

function redeem.configure_codes_for_tests(codes)
  catalog = gift_code_catalog.build(codes)
end

function redeem.reset_for_tests()
  catalog = gift_code_catalog.default()
end

return redeem
