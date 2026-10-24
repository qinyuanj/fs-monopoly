-- 礼包码码表的加载期校验、哈希口径与查码(#198 / #203 / #204 / ADR 0075)。
-- 皮肤归属模块内部:码表数据留在配置层(gift_codes),规则住这里。
-- build 对任意码表、皮肤目录与停用 id 列表校验并建哈希索引,违规以
-- error(msg, 0) 报出;配置码表在 require 时即构建,配置错误随加载暴露。
-- 码表只存 code_hash;查码先规范化输入再算 SHA-256。gift-code new CLI 引用
-- 本模块的 code_hash 算写入码表的哈希,两边口径同一处定义。
local gift_codes = require("src.config.content.gift_codes")
local skins = require("src.config.content.skins")
local number_utils = require("src.foundation.number")
local sha256 = require("src.foundation.sha256")

local gift_code_table = {}

-- 去掉全部空白与连字符并统一为大写;非字符串按空串处理。
function gift_code_table.normalize(text)
  if type(text) ~= "string" then
    return ""
  end
  return string.upper((text:gsub("[%s%-]", "")))
end

-- 规范化后的 SHA-256(64 位小写十六进制),即码表 code_hash 的口径。
function gift_code_table.code_hash(text)
  return sha256.hex(gift_code_table.normalize(text))
end

local function _fail(message)
  error(message, 0)
end

local function _skins_by_product(skin_catalog)
  local by_product = {}
  for _, skin in ipairs(skin_catalog) do
    by_product[skin.product_id] = skin
  end
  return by_product
end

local function _is_positive_integer(value)
  return number_utils.is_numeric(value) and number_utils.to_integer(value) == value and value > 0
end

-- 停用 id 永不再分配(#203):返回 { [id] = true }。
local function _retired_set(retired_ids)
  local retired = {}
  for _, id in ipairs(retired_ids or {}) do
    if not _is_positive_integer(id) then
      _fail("invalid retired gift code id: " .. tostring(id))
    end
    retired[id] = true
  end
  return retired
end

local function _validate_id(entry, seen_ids, retired)
  local id = entry.id
  if not _is_positive_integer(id) then
    _fail("invalid gift code id: " .. tostring(id))
  end
  if seen_ids[id] then
    _fail("duplicate gift code id: " .. tostring(id))
  end
  if retired[id] then
    _fail("gift code id is retired: " .. tostring(id))
  end
  seen_ids[id] = true
end

-- 明文 code 会随客户端分发,出现即拒绝(#203 User Story 22)。
local function _validate_code_hash(entry, by_hash)
  if entry.code ~= nil then
    _fail("gift code must not carry plaintext code: id=" .. tostring(entry.id))
  end
  local code_hash = entry.code_hash
  if type(code_hash) ~= "string" or #code_hash ~= 64 or code_hash:find("[^0-9a-f]") then
    _fail("invalid gift code_hash: id=" .. tostring(entry.id))
  end
  if by_hash[code_hash] ~= nil then
    _fail("duplicate gift code_hash: id=" .. tostring(entry.id))
  end
  return code_hash
end

local function _validate_reward(entry, skin_by_product, product_id)
  local skin = skin_by_product[product_id]
  local suffix = ": id=" .. tostring(entry.id) .. " product_id=" .. tostring(product_id)
  if skin == nil then
    _fail("gift code reward is not a skin" .. suffix)
  end
  if skin.archive_key == nil then
    _fail("gift code reward has no archive_key" .. suffix)
  end
end

local function _validate_rewards(entry, skin_by_product)
  local rewards = entry.rewards
  if type(rewards) ~= "table" or #rewards == 0 then
    _fail("gift code has no rewards: id=" .. tostring(entry.id))
  end
  for _, product_id in ipairs(rewards) do
    _validate_reward(entry, skin_by_product, product_id)
  end
end

-- expires_at 可选,配了就必须是数值(墙钟秒);非数值会在兑换时被静默当
-- 不过期,加载期先拦住(#195 review)。
local function _validate_expires_at(entry)
  local expires_at = entry.expires_at
  if expires_at ~= nil and not number_utils.is_numeric(expires_at) then
    _fail("invalid gift code expires_at: id=" .. tostring(entry.id))
  end
end

-- 返回 { find = function(input_text) -> entry|nil };entry 即码表原条目。
function gift_code_table.build(codes, skin_catalog, retired_ids)
  local skin_by_product = _skins_by_product(skin_catalog or skins)
  local retired = _retired_set(retired_ids)
  local seen_ids = {}
  local by_hash = {}
  for _, entry in ipairs(codes or {}) do
    _validate_id(entry, seen_ids, retired)
    local code_hash = _validate_code_hash(entry, by_hash)
    _validate_rewards(entry, skin_by_product)
    _validate_expires_at(entry)
    by_hash[code_hash] = entry
  end
  return {
    find = function(input_text)
      if gift_code_table.normalize(input_text) == "" then
        return nil
      end
      return by_hash[gift_code_table.code_hash(input_text)]
    end,
  }
end

-- 配置码表的索引按码表与停用表的表身份记忆:配置换表(测试打补丁)即重建并重新校验。
local configured = {}

function gift_code_table.default()
  if configured.codes ~= gift_codes.codes or configured.retired_ids ~= gift_codes.retired_ids then
    configured = {
      codes = gift_codes.codes,
      retired_ids = gift_codes.retired_ids,
      index = gift_code_table.build(gift_codes.codes, skins, gift_codes.retired_ids),
    }
  end
  return configured.index
end

gift_code_table.default()

return gift_code_table
