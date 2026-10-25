-- 皮肤归属的换模型(#204 迁入,#205 收口到端口):按皮肤的模型资源经
-- runtime_ports.set_role_model 换模型,脱下时经 reset_role_model 复位。资源 id
-- 取自运行资产目录;宿主签名与调用形态归 src/host/role_model,本模块不接触宿主对象。
local runtime_ports = require("src.foundation.ports.runtime_ports")
local logger = require("src.foundation.log")
local runtime_assets = require("src.config.runtime_assets")

local model = {}

-- 皮肤缺失/未登记产品/模型无资源时统一 nil。
local function _skin_asset(product_id)
  local resource = runtime_assets.skin_model_for_product(product_id)
  return resource and resource.asset_id or nil
end

local function _default_asset()
  local resource = runtime_assets.default_skin_model()
  return resource and resource.asset_id or nil
end

-- 返回模型是否换成。
function model.equip(role_id, product_id)
  local creature_key = _skin_asset(product_id)
  if creature_key == nil then
    logger.warn("skin_ownership: missing creature_key for player " .. tostring(role_id))
    return false
  end
  if runtime_ports.set_role_model(role_id, creature_key) ~= true then
    logger.warn("skin_ownership: set_role_model failed for player " .. tostring(role_id))
    return false
  end
  return true
end

local function _apply_default_creature(role_id, default_creature_key)
  if runtime_ports.set_role_model(role_id, default_creature_key) ~= true then
    logger.warn("skin_ownership: default creature fallback failed for player " .. tostring(role_id))
    return false
  end
  return true
end

-- 返回模型是否复位。优先让宿主复位;复位失败退回换默认 creature。
function model.unequip(role_id)
  if runtime_ports.reset_role_model(role_id) == true then
    return true
  end
  logger.warn("skin_ownership: reset_role_model failed for player " .. tostring(role_id))
  local default_creature_key = _default_asset()
  if default_creature_key == nil then
    logger.warn("skin_ownership: missing default creature_key fallback for player " .. tostring(role_id))
    return false
  end
  return _apply_default_creature(role_id, default_creature_key)
end

return model
