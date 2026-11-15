---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_platform_boundary.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local boundary = require("foundation.platform_boundary")

describe("platform boundary", function()
  it("renders an unavailable verdict to stderr with exit code 3", function()
    local verdict = boundary.unavailable_verdict("fixture", " tool=x step=y", { "first", "second" })
    check.same("unavailable", verdict.status)
    check.same(3, verdict.exit_code)
    check.same("stderr", verdict.stream)
    check.same("[fixture] status=unavailable tool=x step=y\n[fixture] first\n[fixture] second\n",
      verdict.message)
  end)

  it("offers only the unavailable and real-failure states, no explicit skip protocol", function()
    check.is_nil(boundary.evaluate)
    check.is_nil(boundary.strip_skip_flag)
    check.is_nil(boundary.declared_ids)
    check.is_nil(boundary.SKIP_FLAG)
    check.is_nil(boundary.SKIPPED)
    check.is_nil(boundary.SKIPPED_EXIT_CODE)
  end)

  -- 保证面收窄是**被测事实**,不是注释约定(ADR 0083 / #239):
  -- 只有原生 Windows 在保证面内,linux / macos / posix 一律判不可用。
  it("keeps native Windows as the only supported platform", function()
    check.is_true(boundary.supported_platform("windows"))
    check.is_false(boundary.supported_platform("linux"))
    check.is_false(boundary.supported_platform("macos"))
    check.is_false(boundary.supported_platform("posix"))
    check.same(3, boundary.UNAVAILABLE_EXIT_CODE)
  end)

  it("decides the unsupported platform unavailable instead of silently passing", function()
    local verdict = boundary.platform_verdict("fixture", "linux")
    check.same("unavailable", verdict.status)
    check.same(3, verdict.exit_code)
    check.matches("platform=linux", verdict.message, 1, true)
    check.is_nil(boundary.platform_verdict("fixture", "windows"))
  end)

  it("reports this machine as native Windows", function()
    check.same("windows", boundary.host_platform())
  end)
end)