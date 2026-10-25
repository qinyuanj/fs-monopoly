-- 换模型的宿主侧执行(#205 真机取证,ADR 0046):role.get_ctrl_unit()、
-- unit.set_model_by_creature_key(creature_key, include_custom_model,
-- inherit_scale, inherit_capsule_size)、unit.reset_model() 全部不带 self(冒号
-- 调用被宿主以 params count mismatch 拒收,只记 ERROR 返回 nil、不抛),三个布尔
-- 宿主有默认值但本项目一律显式传 true。两个换模型方法都无返回值,宿主也不提供
-- 可读回的当前模型,成功只能以「调用未抛」判定——参数错误宿主不抛,所以签名
-- 必须以本注释的取证为准,不得试探。规则层只经 runtime_ports 的
-- set_role_model / reset_role_model 触达。
local host_types = require("src.foundation.host_types")
local logger = require("src.foundation.log")

local role_model = {}

-- set_model_by_creature_key 的三个布尔:含自定义形象、继承缩放、继承胶囊体。
local INCLUDE_CUSTOM_MODEL = true
local INHERIT_SCALE = true
local INHERIT_CAPSULE_SIZE = true

local function _warn(player_id, message)
  logger.warn("role_model: " .. message .. " for player " .. tostring(player_id))
end

-- 角色缺失、无 get_ctrl_unit、get_ctrl_unit 抛错、无控制单位各自留痕。
local function _resolve_ctrl_unit(resolve_role, player_id)
  local role = resolve_role(player_id)
  if role == nil then
    _warn(player_id, "no role")
    return nil
  end
  local get_ctrl_unit = host_types.method(role, "get_ctrl_unit")
  if get_ctrl_unit == nil then
    _warn(player_id, "role has no get_ctrl_unit")
    return nil
  end
  local ok, unit = pcall(get_ctrl_unit)
  if not ok then
    _warn(player_id, "get_ctrl_unit raised: " .. tostring(unit))
    return nil
  end
  if unit == nil then
    _warn(player_id, "role has no ctrl unit")
    return nil
  end
  return unit
end

-- 单次直调控制单位上的无返回值方法;返回是否未抛。
local function _call_unit(resolve_role, player_id, method_name, ...)
  local unit = _resolve_ctrl_unit(resolve_role, player_id)
  if unit == nil then
    return false
  end
  local method = host_types.method(unit, method_name)
  if method == nil then
    _warn(player_id, "ctrl unit has no " .. method_name)
    return false
  end
  local ok, err = pcall(method, ...)
  if not ok then
    _warn(player_id, method_name .. " raised: " .. tostring(err))
    return false
  end
  return true
end

-- resolve_role(player_id) 由装配方给出(宿主 Role 或合成 AI 适配器)。
function role_model.install(defaults, resolve_role)
  defaults.set_role_model = function(player_id, creature_key)
    return _call_unit(resolve_role, player_id, "set_model_by_creature_key", creature_key,
      INCLUDE_CUSTOM_MODEL, INHERIT_SCALE, INHERIT_CAPSULE_SIZE)
  end

  defaults.reset_role_model = function(player_id)
    return _call_unit(resolve_role, player_id, "reset_model")
  end
end

return role_model
