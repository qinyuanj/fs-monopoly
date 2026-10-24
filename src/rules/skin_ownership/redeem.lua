-- 礼包码兑换(#198 / #203 / #204 / ADR 0075,皮肤归属内部)。返回结构化结果:
--   { status = <下列之一>, granted = { product_id... } }
--   granted / all_owned / invalid_code / expired / already_redeemed /
--   archive_unavailable / write_failed
-- 奖励与购买、礼物走同一条归属写档路径(ADR 0074 第 1 条);提示文案归礼包码屏。
-- 顺序:存档不可用直接拒绝(不读不写)→ 查码 → 过期 → 读兑换记录 → 发放未拥有
-- 皮肤 → 追加兑换记录并回读核对。记录写档失败不撤销已发归属(ADR 0074 第 3 条),
-- 重试时这些皮肤按已拥有跳过;皮肤归属写档失败则不写记录,留给重试时发放。
local runtime_ports = require("src.foundation.ports.runtime_ports")
local logger = require("src.foundation.log")
local number_utils = require("src.foundation.number")
local archive = require("src.rules.skin_ownership.archive")
local gift_code_table = require("src.rules.skin_ownership.gift_code_table")
local session = require("src.rules.skin_ownership.session")

local redeem = {}

local function _result(status, granted)
  return { status = status, granted = granted or {} }
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

local function _lookup(input_text)
  local entry = gift_code_table.default().find(input_text)
  if entry == nil then
    return nil, _result("invalid_code")
  end
  if _expired(entry) then
    return nil, _result("expired")
  end
  return entry, nil
end

local function _read_record(role_id, entry)
  local text = archive.read_redeem_record(role_id)
  if text == nil then
    _warn("redeem record unreadable", role_id, entry)
    return nil, _result("archive_unavailable")
  end
  if archive.record_contains(text, entry.id) then
    return nil, _result("already_redeemed")
  end
  return text, nil
end

-- 返回 (本次发放列表, 是否全部落档)。
local function _grant_missing(slot, role_id, entry, archived)
  local granted = {}
  local all_persisted = true
  for _, product_id in ipairs(entry.rewards) do
    if archived[product_id] ~= true then
      local marked, persisted = session.mark_owned(slot, role_id, product_id)
      if marked then
        granted[#granted + 1] = product_id
      end
      all_persisted = all_persisted and persisted
    end
  end
  return granted, all_persisted
end

local function _grant_and_record(root_state, role_id, entry, record_text)
  local slot = session.ensure(root_state)
  local archived = slot and session.load_owned(slot, role_id) or nil
  if archived == nil then
    _warn("skin ownership unreadable", role_id, entry)
    return _result("archive_unavailable")
  end
  local granted, all_persisted = _grant_missing(slot, role_id, entry, archived)
  if not all_persisted then
    _warn("skin ownership write failed, record not written", role_id, entry)
    return _result("write_failed", granted)
  end
  if not archive.append_redeem_record(role_id, record_text, entry.id) then
    _warn("redeem record write failed", role_id, entry, "record=" .. tostring(record_text))
    return _result("write_failed", granted)
  end
  if #granted == 0 then
    return _result("all_owned")
  end
  return _result("granted", granted)
end

function redeem.redeem(root_state, role_id, input_text)
  if not archive.enabled() then
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
  return _grant_and_record(root_state, role_id, entry, record_text)
end

return redeem
