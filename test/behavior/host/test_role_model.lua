-- role_model 宿主适配 spec(#205 真机取证,ADR 0046):role.get_ctrl_unit()、
-- unit.set_model_by_creature_key(creature_key, include_custom_model,
-- inherit_scale, inherit_capsule_size)、unit.reset_model() 均不带 self(冒号
-- 调用被宿主以 params count mismatch 拒收)、无返回值。宿主不提供可读回的模型
-- 状态,成功只能以「调用未抛」判定;对象缺失、方法缺失与调用异常各自留痕。
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local role_model = require("src.host.role_model")
local logger = require("src.foundation.log")

-- 按 player_id 查表的角色解析替身,装出两个端口。
local function _ports(roles)
  local defaults = {}
  role_model.install(defaults, function(player_id)
    return roles[player_id]
  end)
  return defaults
end

local function _with_warns(fn)
  local warns = {}
  local result
  support.with_patches({
    {
      target = logger,
      key = "warn",
      value = function(...)
        warns[#warns + 1] = table.concat({ ... }, " ")
      end,
    },
  }, function()
    result = fn()
  end)
  return result, table.concat(warns, "\n")
end

-- 宿主角色替身:get_ctrl_unit 记录实参个数,模拟宿主拒收 self。
local function _host_role(unit)
  local role = { ctrl_arg_counts = {} }
  role.get_ctrl_unit = function(...)
    role.ctrl_arg_counts[#role.ctrl_arg_counts + 1] = select("#", ...)
    return unit
  end
  return role
end

-- 宿主单位替身:两个换模型方法均无返回值,只记录实参。
local function _host_unit(opts)
  opts = opts or {}
  local unit = { set_calls = {}, reset_calls = {} }
  unit.set_model_by_creature_key = function(...)
    unit.set_calls[#unit.set_calls + 1] = table.pack(...)
    if opts.set_raises then
      error("host set_model boom")
    end
  end
  unit.reset_model = function(...)
    unit.reset_calls[#unit.reset_calls + 1] = table.pack(...)
    if opts.reset_raises then
      error("host reset_model boom")
    end
  end
  return unit
end

describe("TestRoleModel", function()
  it("test_set_role_model_calls_the_setter_once_without_self_and_with_full_flags", function()
    local unit = _host_unit()
    local role = _host_role(unit)

    luassert.is_true(_ports({ [7] = role }).set_role_model(7, 1073909878))

    luassert.same({ 0 }, role.ctrl_arg_counts, "get_ctrl_unit takes no self")
    luassert.same({ { n = 4, 1073909878, true, true, true } }, unit.set_calls,
      "single direct call (creature_key, true, true, true)")
  end)

  it("test_reset_role_model_calls_reset_once_without_self", function()
    local unit = _host_unit()

    luassert.is_true(_ports({ [7] = _host_role(unit) }).reset_role_model(7))

    luassert.same({ { n = 0 } }, unit.reset_calls, "single direct call with no arguments")
    luassert.same({}, unit.set_calls, "reset never touches the setter")
  end)

  it("test_raising_host_calls_fail_with_warn_and_are_not_retried", function()
    local unit = _host_unit({ set_raises = true, reset_raises = true })
    local ports = _ports({ [7] = _host_role(unit) })

    local set_ok, set_warns = _with_warns(function()
      return ports.set_role_model(7, 42)
    end)
    local reset_ok, reset_warns = _with_warns(function()
      return ports.reset_role_model(7)
    end)

    luassert.is_false(set_ok)
    luassert.is_false(reset_ok)
    -- lint-allow: call-count 单次直调契约:宿主抛错后不再换签名重试
    luassert.equal(1, #unit.set_calls)
    -- lint-allow: call-count 单次直调契约:宿主抛错后不再换签名重试
    luassert.equal(1, #unit.reset_calls)
    luassert.truthy(set_warns:find("set_model_by_creature_key raised", 1, true)
      and set_warns:find("player 7", 1, true), set_warns)
    luassert.truthy(reset_warns:find("reset_model raised", 1, true), reset_warns)
  end)

  it("test_each_missing_object_or_method_fails_with_its_own_warn", function()
    local cases = {
      { roles = {}, expect = "no role" },
      { roles = { [7] = {} }, expect = "no get_ctrl_unit" },
      { roles = { [7] = { get_ctrl_unit = function() error("ctrl boom") end } }, expect = "get_ctrl_unit raised" },
      { roles = { [7] = _host_role(nil) }, expect = "no ctrl unit" },
      { roles = { [7] = _host_role({}) }, expect = "has no set_model_by_creature_key" },
    }
    for _, case in ipairs(cases) do
      local ok, warns = _with_warns(function()
        return _ports(case.roles).set_role_model(7, 42)
      end)
      luassert.is_false(ok, case.expect)
      luassert.truthy(warns:find(case.expect, 1, true) and warns:find("player 7", 1, true), warns)
    end

    local ok, warns = _with_warns(function()
      return _ports({ [7] = _host_role({}) }).reset_role_model(7)
    end)
    luassert.is_false(ok)
    luassert.truthy(warns:find("has no reset_model", 1, true), warns)
  end)
end)
