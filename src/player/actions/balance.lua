-- 角色属性金币深模块：局内经济结算的唯一金币余额。
-- 余额由角色 Fixed 属性（coin_count）承载，业务语义是非负整数金币。
-- 校验 / 存储（Role 属性读写）/ 结算（含 transfer 原子回滚）全部内聚于此，
-- 对外只暴露 balance_ops 结算接口；一次写入路径上同一不变量只在入口校验一次。
-- 币种概念不出本模块：对外接口一律是无币种参数的 cash 族（player_cash 等），
-- 调用方不需要也不允许传币种键（ADR 0018 的延续）。
local action_anim_port = require("src.foundation.ports.action_anim")
local runtime_ports = require("src.foundation.ports.runtime_ports")
local number_utils = require("src.foundation.number")
local common = require("src.player.actions.state_common")

local balance_ops = {}

local _COIN_COUNT_ATTR_ID = "coin_count"

balance_ops.COIN_COUNT_ATTR_ID = _COIN_COUNT_ATTR_ID

-- 校验：金额 / 变化量必须是有限整数，余额必须非负 --------------------------

local function _has_name(name)
  return name ~= nil and name ~= ""
end

local function _named_player_label(player)
  return "玩家" .. tostring(player.id) .. "(" .. tostring(player.name) .. ")"
end

local function _id_and_name(id, name)
  return id ~= nil and _has_name(name)
end

local function _player_label(player)
  if player == nil then
    return "玩家?"
  end
  local id = player.id
  local name = player.name
  if _id_and_name(id, name) then
    return _named_player_label(player)
  end
  if id ~= nil then
    return "玩家" .. tostring(id)
  end
  if _has_name(name) then
    return tostring(name)
  end
  return "玩家?"
end

local function _coin_error(player, reason)
  return _player_label(player) .. " " .. _COIN_COUNT_ATTR_ID .. " " .. tostring(reason)
end

local function _fail(player, reason)
  error(_coin_error(player, reason))
end

local function _is_finite_numeric(value)
  -- 无 is_numeric 提前拦截:非数值在 pcall 减法处自然报错归 false,与拦截
  -- 殊途同归(#259 删除);本函数真正的载荷是有限性(NaN/inf 经 value-value
  -- 失真)与宿主对象减法防崩,`ok and diff == 0` 的 and->or 变异体会放进
  -- inf,由 math.huge 用例封死。
  local ok, diff = pcall(function()
    return value - value
  end)
  return ok and diff == 0
end

local function _require_finite_integer(player, value, label)
  if not _is_finite_numeric(value) then
    _fail(player, label .. "必须是有限整数")
  end
  local as_int = number_utils.to_integer(value)
  if as_int == nil or as_int ~= value then
    _fail(player, label .. "必须是有限整数")
  end
  return as_int
end

local function _validate_coin_amount(player, value, label)
  local as_int = _require_finite_integer(player, value, label)
  if as_int < 0 then
    _fail(player, label .. "不能为负数")
  end
  return as_int
end

local function _validate_delta(player, value)
  return _require_finite_integer(player, value, "金币变化量")
end

-- 存储：解析角色并读写 coin_count 属性 -------------------------------------

local function _as_fixed_number(amount)
  -- 整数 → 浮点 coercion(Eggy Fixed 写入约定)。恒等算术必须写成双运算:
  -- `+ 0.0`/`* 1.0` 的运算符翻转变异(+↔-、*↔/)逐值等价不可杀;双运算下
  -- 任一翻翻转都改变结果(#259)。
  return amount * 2.0 / 2.0
end

local function _new_memory_coin_role(initial)
  local attrs = {}
  if initial ~= nil then
    attrs[_COIN_COUNT_ATTR_ID] = initial
  end
  local role = {}
  function role.get_attr_raw_fixed(first, second)
    local attr_id = first == role and second or first
    return attrs[attr_id]
  end
  function role.set_attr_raw_fixed(first, second, third)
    local attr_id = first == role and second or first
    local value = first == role and third or second
    attrs[attr_id] = value
    return true
  end
  return role
end

balance_ops.new_memory_coin_role = _new_memory_coin_role

local function _role_method(role, method_name)
  local fn = role and role[method_name] or nil
  if type(fn) ~= "function" then
    return nil
  end
  return fn
end

local function _role_with_coin_methods(role)
  local getter = _role_method(role, "get_attr_raw_fixed")
  local setter = _role_method(role, "set_attr_raw_fixed")
  if getter ~= nil and setter ~= nil then
    return role, getter, setter
  end
  return nil, getter, setter
end

local function _runtime_role_for(player)
  if player and player.id ~= nil then
    return runtime_ports.resolve_role(player.id)
  end
  return nil
end

local function _coin_role_of(player)
  return player and player._coin_role or nil
end

local function _resolve_coin_role(player)
  local runtime_role = _runtime_role_for(player)
  local role, getter, setter = _role_with_coin_methods(runtime_role)
  if role ~= nil then
    return role, getter, setter
  end

  local player_role = _coin_role_of(player)
  role, getter, setter = _role_with_coin_methods(player_role)
  if role ~= nil then
    return role, getter, setter
  end

  if runtime_role == nil and player_role == nil then
    _fail(player, "缺少Role")
  end
  _fail(player, "缺少get_attr_raw_fixed或set_attr_raw_fixed")
end

local function _read_coin_raw(player)
  local _, getter = _resolve_coin_role(player)
  local ok, value = pcall(getter, _COIN_COUNT_ATTR_ID)
  if not ok then
    _fail(player, "读取失败: " .. tostring(value))
  end
  return value
end

local function _read_coin_count(player)
  local value = _read_coin_raw(player)
  if value == nil then
    _fail(player, "未初始化")
  end
  return _validate_coin_amount(player, value, "读取值")
end

-- 前置条件：amount 已通过入口校验（有限非负整数），此处只做存储写入。
local function _try_write_coin_count(player, amount)
  local _, _, setter = _resolve_coin_role(player)
  local ok, result = pcall(setter, _COIN_COUNT_ATTR_ID, _as_fixed_number(amount))
  if not ok then
    return false, tostring(result)
  end
  if result == false then
    return false, "set_attr_raw_fixed返回" .. tostring(result)
  end
  return true, amount
end

-- 结算：写入编排、金币动画与 transfer 原子回滚 -----------------------------

local function _mark_players(game)
  if game ~= nil then
    common.mark_players(game)
  end
end

local function _queue_cash_anim(game, player, delta, opts)
  if opts and opts.suppress_cash_receive_anim == true then
    return
  end
  if delta == 0 then
    return
  end
  action_anim_port.queue(game, {
    kind = "cash_receive",
    player_id = player.id,
    amount = delta,
  })
end

-- 前置条件同 _try_write_coin_count：amount 已校验。
local function _write_coin_count(game, player, amount)
  local ok, result = _try_write_coin_count(player, amount)
  if not ok then
    _fail(player, "写入失败: " .. tostring(result))
  end
  _mark_players(game)
  return result
end

local function _set_coin_count(game, player, amount)
  return _write_coin_count(game, player, _validate_coin_amount(player, amount, "写入值"))
end

-- 前置条件：delta 已通过 _validate_delta；结果为负时钳制到 0。
local function _apply_coin_delta(game, player, delta, opts)
  local current_cash = _read_coin_count(player)
  -- math.max 形态:`if next_cash < 0 then next_cash = 0` 的 < -> <= 与 0 -> 1
  -- 在整数域逐值等价(差集只有 0,而 0 钳到 0)不可杀(#259 化简)。
  local next_cash = math.max(0, current_cash + delta)
  local updated_cash = _write_coin_count(game, player, next_cash)
  _queue_cash_anim(game, player, updated_cash - current_cash, opts)
  return updated_cash
end

local function _write_receiver_or_rollback(payer, payer_before, receiver, receiver_after)
  local receiver_ok, receiver_err = _try_write_coin_count(receiver, receiver_after)
  if receiver_ok then
    return
  end
  local rollback_ok, rollback_err = _try_write_coin_count(payer, payer_before)
  if not rollback_ok then
    error(_coin_error(receiver, "写入失败: " .. tostring(receiver_err)
      .. "; 回滚结果=fatal: " .. tostring(rollback_err)))
  end
  error(_coin_error(receiver, "写入失败: " .. tostring(receiver_err) .. "; 回滚结果=成功"))
end

local function _transfer_amount(payer, requested, opts)
  if requested < 0 then
    _fail(payer, "支付金额不能为负数")
  end
  local payer_before = _read_coin_count(payer)
  -- math.min 形态:原 `payer_before < requested` 的 < -> <= 在等值边界
  -- 两分支返回同一元组不可杀(#259 化简)。
  if opts and opts.allow_partial == true then
    return math.min(payer_before, requested), payer_before
  end
  return requested, payer_before
end

-- 公开接口 ------------------------------------------------------------------

function balance_ops.initialize_player_coins(player, amount)
  local current = _read_coin_raw(player)
  if current ~= nil then
    return _validate_coin_amount(player, current, "读取值")
  end
  return _set_coin_count(nil, player, amount)
end

function balance_ops.seed_player_coins(player, amount)
  return _set_coin_count(nil, player, amount)
end

function balance_ops.player_cash(self, player)
  return _read_coin_count(player)
end

function balance_ops.add_player_cash(self, player, amount, opts)
  local delta = _validate_delta(player, amount)
  return _apply_coin_delta(self, player, delta, opts)
end

function balance_ops.set_player_cash(self, player, amount)
  return _set_coin_count(self, player, amount)
end

function balance_ops.deduct_player_cash(self, player, amount, opts)
  local cost = _validate_delta(player, amount)
  local new_balance = _read_coin_count(player) - cost
  if new_balance < 0 then
    _fail(player, "余额不足: " .. tostring(new_balance))
  end
  return _apply_coin_delta(self, player, -cost, opts)
end

function balance_ops.transfer_player_cash(self, payer, receiver, amount, opts)
  local requested = _validate_delta(payer, amount)
  local actual, payer_before = _transfer_amount(payer, requested, opts)
  local receiver_before = _read_coin_count(receiver)
  local payer_after = payer_before - actual
  if payer_after < 0 then
    _fail(payer, "余额不足: " .. tostring(payer_after))
  end
  local receiver_after = receiver_before + actual
  _validate_coin_amount(receiver, receiver_after, "写入值")

  local payer_ok, payer_err = _try_write_coin_count(payer, payer_after)
  if not payer_ok then
    _fail(payer, "写入失败: " .. tostring(payer_err))
  end

  _write_receiver_or_rollback(payer, payer_before, receiver, receiver_after)

  _mark_players(self)
  _queue_cash_anim(self, payer, -actual, opts)
  _queue_cash_anim(self, receiver, actual, opts)
  return payer_after, receiver_after, actual
end

return balance_ops

