require("test.bootstrap").install_package_paths()
-- busted injects the extensible assertion object into each file environment.
-- luacheck: ignore 143
local luassert = assert
local support = require("test.support.shared_support")
local share_panel = require("src.foundation.ports.share_panel")

local function _assert_eq(a, b, msg) luassert.is.equal(b, a, msg) end

-- share_panel 是纯契约 port(#463):宿主调用实现在 src/host/share_panel,
-- 由装配侧 configure 注入(host_install / 测试基线),本文件不反向依赖实现。
-- 测试用假实现钉转发契约:actor_role_id/tag 参数与返回值原样穿透;
-- 未配置时 try_show 安全降级返回 false 而非报错(分享面板是锦上添花能力,
-- 装配遗漏不该砸断调用方)。

describe("TestSharePanelPort", function()

  before_each(function()
    share_panel.reset_for_tests()
  end)

  after_each(function()
    support.restore_runtime_services()
  end)

  local function _fake_impl(seen)
    return {
      try_show = function(actor_role_id, tag)
        seen.actor_role_id = actor_role_id
        seen.tag = tag
        return "impl_ret"
      end,
    }
  end

  local function _expect_error(fragment, fn)
    local ok, err = pcall(fn)
    luassert.truthy(ok == false, "call should raise")
    luassert.truthy(tostring(err):find(fragment, 1, true) ~= nil, "error should mention: " .. tostring(fragment) .. ", got: " .. tostring(err))
  end

  it("test_try_show_forwards_to_the_configured_impl", function()
    local seen = {}
    share_panel.configure(_fake_impl(seen))
    local ret = share_panel.try_show(7, "share button")
    _assert_eq(ret, "impl_ret", "return value must pass through")
    _assert_eq(seen.actor_role_id, 7, "actor_role_id must pass through")
    _assert_eq(seen.tag, "share button", "tag must pass through")
  end)

  it("test_try_show_without_a_configured_impl_degrades_to_false", function()
    _assert_eq(share_panel.try_show(1), false, "unconfigured port must degrade to false, not raise")
    _assert_eq(share_panel.try_show(nil, "auto share panel"), false,
      "unconfigured port must degrade to false for any arguments")
  end)

  it("test_reset_for_tests_clears_the_configured_impl", function()
    share_panel.configure(_fake_impl({}))
    share_panel.reset_for_tests()
    _assert_eq(share_panel.try_show(1), false, "reset must return the port to the unconfigured fallback")
  end)

  it("test_configure_rejects_an_impl_missing_try_show", function()
    _expect_error("missing try_show", function()
      share_panel.configure({})
    end)
  end)

  it("test_configure_rejects_a_non_table_impl", function()
    _expect_error("invalid share_panel implementation", function()
      share_panel.configure(nil)
    end)
  end)

  it("test_is_configured_reflects_the_configuration_state", function()
    luassert.truthy(share_panel.is_configured() == false, "a fresh port starts unconfigured")
    share_panel.configure(_fake_impl({}))
    luassert.truthy(share_panel.is_configured() == true, "a configured port reports configured")
    share_panel.reset_for_tests()
    luassert.truthy(share_panel.is_configured() == false, "reset returns to unconfigured")
  end)

end)
