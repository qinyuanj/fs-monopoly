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

  -- 候选 4:判决 → 文本只有一个公开渲染点。message 是它的产物(既有断言逐字钉住),
  -- 手工拼的判决没有 message 时也按 tag/fields/lines 现场渲染。
  it("renders a verdict through one public renderer", function()
    local verdict = boundary.unavailable_verdict("fixture", " tool=x step=y", { "first" })
    check.equal(verdict.message, boundary.render(verdict))
    check.equal("[fixture] status=unavailable tool=x step=y\n[fixture] first\n",
      boundary.render({ status = "unavailable", tag = "fixture", fields = " tool=x step=y", lines = { "first" } }))
  end)

  -- 写终端只有一个出口:调用点可以交自己的流(子命令的注入缝常常只提供 write)。
  it("emits to a caller-supplied stream that offers only write", function()
    local chunks = {}
    local sink = { write = function(_, text) chunks[#chunks + 1] = text end }
    local code = boundary.emit(boundary.unavailable_verdict("fixture", " step=y", { "body" }), sink)
    check.same(3, code)
    check.same("[fixture] status=unavailable step=y\n[fixture] body\n", table.concat(chunks))
  end)

  -- 能 flush 的流必须真的被 flush:替身把 write 的内容先攒着,只有 flush 才落到
  -- 目的地。断言的是「文本到没到」这个可见结果,不是 flush 被调了几次。
  it("flushes streams that provide flush so the text reaches the destination", function()
    local pending, delivered = "", ""
    local sink = {
      write = function(_, text) pending = pending .. text end,
      flush = function()
        delivered = delivered .. pending
        pending = ""
      end,
    }
    boundary.emit(boundary.unavailable_verdict("fixture", " step=flushed", {}), sink)
    check.same("[fixture] status=unavailable step=flushed\n", delivered)
  end)

  -- 不传第二参时仍按判决的 stream 选流(tools/cli.lua 就是这种调用形态)。
  it("defaults the stream from the verdict", function()
    local real_stdout, real_stderr = io.stdout, io.stderr
    local written = { stdout = "", stderr = "" }
    local function sink(key)
      return {
        write = function(_, text) written[key] = written[key] .. text end,
        flush = function() end,
      }
    end
    -- rawset:与 test_log / test_tool_cli 同惯例,避免 W122(io.stdout 是只读字段)。
    local ok, err = pcall(function()
      rawset(io, "stdout", sink("stdout"))
      rawset(io, "stderr", sink("stderr"))
      boundary.emit(boundary.unavailable_verdict("fixture", " step=stderr", {}))
      local stdout_verdict = boundary.unavailable_verdict("fixture", " step=stdout", {})
      stdout_verdict.stream = "stdout"
      boundary.emit(stdout_verdict)
    end)
    rawset(io, "stdout", real_stdout)
    rawset(io, "stderr", real_stderr)
    check.is_true(ok, err)
    check.truthy(written.stderr:find("step=stderr", 1, true) ~= nil, written.stderr)
    check.truthy(written.stdout:find("step=stdout", 1, true) ~= nil, written.stdout)
    check.is_nil(written.stderr:find("step=stdout", 1, true), written.stderr)
  end)

  -- 不可用诊断的唯一写出入口:组装、渲染、写流、返回退出码一条链。
  it("emits an unavailable diagnostic and returns its exit code", function()
    local chunks = {}
    local sink = { write = function(_, text) chunks[#chunks + 1] = text end }
    local code = boundary.emit_unavailable("probe", " tool=editor-cli step=status", { "detail" }, sink)
    check.same(3, code)
    check.same("[probe] status=unavailable tool=editor-cli step=status\n[probe] detail\n", table.concat(chunks))
  end)
end)