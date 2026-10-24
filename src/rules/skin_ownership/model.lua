-- 皮肤归属的换模型(#204,自 rules/cosmetics 与装配层换装回调迁入):经
-- runtime_ports 解析角色控制单位,按皮肤的模型资源换模型,脱下时复位。
-- 资源 id 取自运行资产目录;宿主 set_model 调用约定不定,按序试探。
local runtime_ports = require("src.foundation.ports.runtime_ports")
local logger = require("src.foundation.log")
local runtime_assets = require("src.config.runtime_assets")

local model = {}

local function _resolve_unit(role_id)
  local role = runtime_ports.resolve_role(role_id)
  if not (role and type(role.get_ctrl_unit) == "function") then
    logger.warn("skin_ownership: no role found for player " .. tostring(role_id))
    return nil
  end
  local ok_unit, unit = pcall(role.get_ctrl_unit)
  if not ok_unit then
    logger.warn("skin_ownership: role get_ctrl_unit failed for player " .. tostring(role_id))
    return nil
  end
  return unit
end

-- 宿主 set_model 的调用约定不定(带不带 self、几个参数),按顺序试探。
local function _try_set_model(set_model, unit, creature_key)
  return pcall(set_model, creature_key, true, true, true)
      or pcall(set_model, unit, creature_key, true, true, true)
      or pcall(set_model, creature_key)
      or pcall(set_model, unit, creature_key)
end

local function _apply_model(unit, creature_key)
  local set_model = unit and unit.set_model_by_creature_key
  if type(set_model) ~= "function" then
    return false
  end
  return _try_set_model(set_model, unit, creature_key)
end

local function _apply_reset_model(unit)
  local reset_model = unit.reset_model
  return pcall(reset_model) or pcall(reset_model, unit)
end

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
  local unit = _resolve_unit(role_id)
  if unit == nil then
    return false
  end
  local ok_change = _apply_model(unit, creature_key)
  if not ok_change then
    logger.warn("skin_ownership: set_model_by_creature_key failed for player " .. tostring(role_id))
  end
  return ok_change == true
end

-- 优先让宿主 reset_model 复位;宿主没这个方法、或复位失败,都退回换默认 creature。
local function _try_reset_model(unit, role_id)
  if type(unit.reset_model) ~= "function" then
    return false
  end
  if _apply_reset_model(unit) then
    return true
  end
  logger.warn("skin_ownership: reset_model failed for player " .. tostring(role_id))
  return false
end

local function _apply_default_creature(unit, role_id, default_creature_key)
  local ok_change = _apply_model(unit, default_creature_key)
  if not ok_change then
    logger.warn("skin_ownership: default creature fallback failed for player " .. tostring(role_id))
  end
  return ok_change == true
end

-- 返回模型是否复位。
function model.unequip(role_id)
  local unit = _resolve_unit(role_id)
  if unit == nil then
    return false
  end
  if _try_reset_model(unit, role_id) then
    return true
  end
  local default_creature_key = _default_asset()
  if default_creature_key == nil then
    logger.warn("skin_ownership: missing default creature_key fallback for player " .. tostring(role_id))
    return false
  end
  return _apply_default_creature(unit, role_id, default_creature_key)
end

return model
