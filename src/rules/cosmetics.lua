local runtime_ports = require("src.foundation.ports.runtime_ports")
local logger = require("src.foundation.log")

local skin_equip = {}

local function _resolve_unit(role_id)
  local role = runtime_ports.resolve_role(role_id)
  if not (role and type(role.get_ctrl_unit) == "function") then
    logger.warn("skin_equip: no role found for player " .. tostring(role_id))
    return nil
  end
  local ok_unit, unit = pcall(role.get_ctrl_unit)
  if not ok_unit then
    logger.warn("skin_equip: role get_ctrl_unit failed for player " .. tostring(role_id))
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

function skin_equip.equip(role_id, creature_key)
  if creature_key == nil then
    logger.warn("skin_equip: missing creature_key for player " .. tostring(role_id))
    return false
  end
  local unit = _resolve_unit(role_id)
  if unit == nil then
    return false
  end
  local ok_change = _apply_model(unit, creature_key)
  if not ok_change then
    logger.warn("skin_equip: set_model_by_creature_key failed for player " .. tostring(role_id))
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
  logger.warn("skin_equip: reset_model failed for player " .. tostring(role_id))
  return false
end

local function _apply_default_creature(unit, role_id, default_creature_key)
  local ok_change = _apply_model(unit, default_creature_key)
  if not ok_change then
    logger.warn("skin_equip: default creature fallback failed for player " .. tostring(role_id))
  end
  return ok_change == true
end

function skin_equip.unequip(role_id, default_creature_key)
  local unit = _resolve_unit(role_id)
  if unit == nil then
    return false
  end
  if _try_reset_model(unit, role_id) then
    return true
  end
  if default_creature_key == nil then
    logger.warn("skin_equip: missing default creature_key fallback for player " .. tostring(role_id))
    return false
  end
  return _apply_default_creature(unit, role_id, default_creature_key)
end

return skin_equip

