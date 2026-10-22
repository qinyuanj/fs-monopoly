-- 礼包码码表的加载期校验与查码(#198 / ADR 0075,User Story 18)。
-- build 对任意码表与皮肤目录校验并建索引,违规以 error(msg, 0) 报出;
-- 默认码表在 require 时即构建,配置错误随加载暴露。
local gift_codes = require("src.config.content.gift_codes")
local skins = require("src.config.content.skins")
local number_utils = require("src.foundation.number")

local gift_code_catalog = {}

-- 去首尾空格并统一为大写;非字符串按空串处理。
function gift_code_catalog.normalize(text)
  if type(text) ~= "string" then
    return ""
  end
  local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
  return string.upper(trimmed)
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

local function _validate_id(entry, seen_ids)
  local id = entry.id
  if not _is_positive_integer(id) then
    _fail("invalid gift code id: " .. tostring(id))
  end
  if seen_ids[id] then
    _fail("duplicate gift code id: " .. tostring(id))
  end
  seen_ids[id] = true
end

local function _validate_code(entry, by_code)
  local normalized = gift_code_catalog.normalize(entry.code)
  if normalized == "" then
    _fail("empty gift code: id=" .. tostring(entry.id))
  end
  if by_code[normalized] ~= nil then
    _fail("duplicate gift code: " .. normalized)
  end
  return normalized
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

-- 返回 { find = function(input_text) -> entry|nil };entry 即码表原条目。
function gift_code_catalog.build(codes, skin_catalog)
  local skin_by_product = _skins_by_product(skin_catalog or skins)
  local seen_ids = {}
  local by_code = {}
  for _, entry in ipairs(codes or {}) do
    _validate_id(entry, seen_ids)
    local normalized = _validate_code(entry, by_code)
    _validate_rewards(entry, skin_by_product)
    by_code[normalized] = entry
  end
  return {
    find = function(input_text)
      return by_code[gift_code_catalog.normalize(input_text)]
    end,
  }
end

local default_catalog = gift_code_catalog.build(gift_codes.codes, skins)

function gift_code_catalog.default()
  return default_catalog
end

return gift_code_catalog
