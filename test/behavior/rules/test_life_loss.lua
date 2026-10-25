-- life_loss(ADR 0046):规则层经 runtime_ports.call_role_die 触达宿主
-- role.die,不再直接摸宿主对象与组件系统;成功判据 = 端口返回 true。
require("test.bootstrap").install_package_paths()
local luassert = assert
local support = require("test.support.shared_support")
local life_loss = require("src.rules.elimination.life_loss")
local runtime_ports = require("src.foundation.ports.runtime_ports")

describe("TestLifeLoss", function()
it("test_try_call_life_die_returns_false_for_nil_role", function()
  local called = false
  support.with_patches({
    {
      target = runtime_ports,
      key = "call_role_die",
      value = function()
        called = true
        return true
      end,
    },
  }, function()
    luassert.truthy(life_loss.try_call_life_die(nil) == false,
      "nil role yields false without touching the port")
  end)
  luassert.truthy(called == false, "nil role must not reach the host port")
end)

it("test_try_call_life_die_delegates_to_the_runtime_port", function()
  local seen = nil
  local result = nil
  support.with_patches({
    {
      target = runtime_ports,
      key = "call_role_die",
      value = function(role)
        seen = role
        return true
      end,
    },
  }, function()
    result = life_loss.try_call_life_die({ id = 1 })
  end)
  luassert.truthy(result == true, "a truthy port result yields true")
  luassert.truthy(seen ~= nil and seen.id == 1, "the port must receive the role")
end)

it("test_try_call_life_die_returns_false_when_port_returns_false", function()
  local result = nil
  support.with_patches({
    {
      target = runtime_ports,
      key = "call_role_die",
      value = function()
        return false
      end,
    },
  }, function()
    result = life_loss.try_call_life_die({ id = 2 })
  end)
  luassert.truthy(result == false, "a falsy port result yields false")
end)

-- 以下三条走共享基线的真实默认端口(role_die 宿主适配),钉宿主直调语义。
it("test_try_call_life_die_returns_false_when_role_die_throws", function()
  local role = {
    die = function()
      error("host die failed")
    end,
  }
  luassert.truthy(life_loss.try_call_life_die(role) == false,
    "a throwing role.die must yield false")
end)

it("test_try_call_life_die_returns_false_when_role_has_no_die_method", function()
  luassert.truthy(life_loss.try_call_life_die({}) == false,
    "a role without die yields false")
end)

it("test_try_call_life_die_returns_true_when_role_die_succeeds", function()
  local role = {
    die = function()
      return true
    end,
  }
  luassert.truthy(life_loss.try_call_life_die(role) == true,
    "a succeeding role.die yields true")
end)

-- 宿主真人 Role(#610):自身无 die,出局经控制单位完成,规则层判据不变。
it("test_try_call_life_die_returns_true_for_a_host_role_with_a_ctrl_unit", function()
  local unit = { dead = false }
  unit.die = function()
    unit.dead = true
  end
  unit.is_die_status = function()
    return unit.dead
  end
  local role = {
    get_ctrl_unit = function()
      return unit
    end,
  }
  local result
  support.with_patches({
    { key = "GameAPI", value = { destroy_unit = function() end } },
  }, function()
    result = life_loss.try_call_life_die(role)
  end)
  luassert.truthy(result == true, "a host role whose ctrl unit dies yields true")
  luassert.truthy(unit.dead == true, "the ctrl unit must end up in die status")
end)

end)
