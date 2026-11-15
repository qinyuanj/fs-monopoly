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

  -- #234 F2:平台判决必须真的接到入口——非 Windows 时跑 `lua tools/cli.lua <子命令>`
  -- 要打 status=unavailable 并退 3,而不是照跑子命令后以 1 收场。测试用 dofile 驱动
  -- + 注入平台判定,不真换操作系统。
  it("cli entry exits 3 with status=unavailable on a non-Windows platform", function()
    local env_lib = require("foundation.env")
    local fs = require("foundation.fs")
    local proc = require("foundation.proc")
    local lua54 = require("foundation.lua54")
    local root = env_lib.make_temp_path("cli_platform_gate", "")
    local ok, err = xpcall(function()
      check.truthy(fs.ensure_dir(root))
      local driver = root .. "/driver.lua"
      check.truthy(fs.write_file(driver, table.concat({
        'package.path = package.path .. ";./tools/?.lua;./tools/?/init.lua"',
        'local boundary = require("foundation.platform_boundary")',
        'boundary.host_platform = function() return "linux" end',
        'arg = { "lint" }',
        'dofile("tools/cli.lua")',
        "",
      }, "\n")))
      local result = proc.run_command({ lua54.lua54_bin(), driver }, { cwd = env_lib.current_dir() })
      check.equal(3, result.code, result.output)
      check.truthy(tostring(result.output):find("[cli] status=unavailable", 1, true), result.output)
      check.truthy(tostring(result.output):find("platform=linux", 1, true), result.output)
    end, debug.traceback)
    fs.remove_path(root)
    check.is_true(ok, err)
  end)
end)