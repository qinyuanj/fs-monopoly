-- 破产出局的宿主侧执行(ADR 0046,取证结论以 #610 为准):宿主 CampRole 没有
-- die,die 在 role.get_ctrl_unit() 返回的单位上,签名单参可省、不带 self、无返回
-- 值,成功信号是 unit.is_die_status() 翻 true;合成 AI 适配器是 Lua table,自带
-- die 返回布尔并自行退役销毁单位,仍按 truthy 判定,由自竖的 is_synthetic_actor
-- 标志认领。两类对象的鸭子知识(方法在谁身上、签名、成功判据)全部收在本模块,
-- 规则层只经 runtime_ports.call_role_die 触达。
local host_types = require("src.foundation.host_types")
local unit_lifecycle = require("src.host.units")
local logger = require("src.foundation.log")

local role_die = {}

-- 合成 AI 适配器路径:die 有明确布尔返回值,成功判据仍是 truthy(#263 探到的
-- 就是这个适配器)。pcall 只防异常炸穿规则层,抛错与假值都留痕。
local function _call_adapter_die(die)
  local ok, result = pcall(die)
  if not ok then
    logger.warn("role_die failed: adapter die raised:", tostring(result))
    return false
  end
  if result == nil or result == false then
    logger.warn("role_die failed: adapter die returned falsy:", tostring(result))
    return false
  end
  return true
end

-- 宿主 Role 无 die 时经控制单位出局;取不到单位即对象缺失,留痕后放弃。
local function _resolve_ctrl_unit(role)
  local get_ctrl_unit = host_types.method(role, "get_ctrl_unit")
  if get_ctrl_unit == nil then
    logger.warn("role_die skip: role has neither die nor get_ctrl_unit")
    return nil
  end
  local ok, unit = pcall(get_ctrl_unit)
  if not ok then
    logger.warn("role_die skip: get_ctrl_unit raised:", tostring(unit))
    return nil
  end
  if unit == nil then
    logger.warn("role_die skip: role has no ctrl unit")
    return nil
  end
  return unit
end

-- unit.die(dmg_unit) 单参、不带 self(冒号调用被宿主拒收),且无返回值——参数
-- 出错时宿主只记 ERROR 返回 nil、不抛异常,所以「pcall 没抛」不是成功信号,一律
-- 回读 is_die_status。已死单位再调 die 幂等,回读同样为 true。
local function _kill_ctrl_unit(unit)
  local die = host_types.method(unit, "die")
  if die == nil then
    logger.warn("role_die skip: ctrl unit has no die method")
    return false
  end
  local is_die_status = host_types.method(unit, "is_die_status")
  if is_die_status == nil then
    logger.warn("role_die skip: ctrl unit has no is_die_status method")
    return false
  end
  local ok, err = pcall(die, nil)
  if not ok then
    logger.warn("role_die failed: ctrl unit die raised:", tostring(err))
    return false
  end
  local ok_status, status = pcall(is_die_status)
  if not (ok_status and status == true) then
    logger.warn("role_die failed: ctrl unit is_die_status not true after die:", tostring(status))
    return false
  end
  return true
end

-- 单位移除调与合成 AI 退役同一个宿主入口 GameAPI.destroy_unit(取句柄的路子不
-- 同但同源:registry 读 ctx.env.GameAPI,本模块经 src/host/units 读全局,而
-- host_install 正是用全局 GameAPI 填的 ctx.env),两类玩家一致。
-- 真机验证待主会话完成:若销毁真人控制单位触发宿主重生或镜头异常,退到隐藏路径
-- (LCharacter 上有 destroy、无 set_visible,隐藏手段需另行取证)。出局语义已由
-- is_die_status 达成,移除失败只留痕、不推翻端口成功(ADR 0046)。
local function _remove_ctrl_unit(unit)
  local ok, destroyed = pcall(unit_lifecycle.destroy_unit, unit)
  if not ok then
    logger.warn("role_die: ctrl unit destroy raised:", tostring(destroyed))
    return
  end
  if destroyed ~= true then
    logger.warn("role_die: ctrl unit destroy skipped: missing GameAPI.destroy_unit")
  end
end

-- 分派不看「role 上有没有 die」——那正是 #263 误判的形状:宿主 Role 哪天长出
-- die,真人就会静默退回已被证伪的 truthy 路径。合成适配器由自己竖的
-- is_synthetic_actor 标志认领(synthetic_actor_registry 建适配器时置位),其余对象
-- 一律走控制单位;只有既无标志又无 get_ctrl_unit 的鸭子替身才回落到自带 die。
local function _is_synthetic_adapter(role)
  return host_types.field(role, "is_synthetic_actor") == true
end

-- 返回 true 表示宿主侧出局处理成功。对象缺失、方法缺失、调用后状态未翻转与移除
-- 失败四类各自留一条 warn,禁止静默。
function role_die.call_role_die(role)
  if role == nil then
    logger.warn("role_die skip: role is nil")
    return false
  end
  if _is_synthetic_adapter(role) then
    local adapter_die = host_types.method(role, "die")
    if adapter_die == nil then
      logger.warn("role_die skip: synthetic adapter has no die method")
      return false
    end
    return _call_adapter_die(adapter_die)
  end
  if host_types.method(role, "get_ctrl_unit") == nil then
    local adapter_die = host_types.method(role, "die")
    if adapter_die ~= nil then
      return _call_adapter_die(adapter_die)
    end
  end
  local unit = _resolve_ctrl_unit(role)
  if unit == nil then
    return false
  end
  if not _kill_ctrl_unit(unit) then
    return false
  end
  _remove_ctrl_unit(unit)
  return true
end

return role_die

