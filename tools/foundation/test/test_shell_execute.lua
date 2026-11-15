---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_shell_execute.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local shell = require("foundation.shell")
local fs = require("foundation.fs")

-- 执行缝的公共行为(ADR 0083 / #235):全仓唯一的命令执行入口,一律经 bash。
-- 断言只看 → 退出码 / 落盘结果 / 诊断文本,不看它内部怎么拼 cmd 行。
describe("shell execute seam", function()
  it("runs a command through bash and reports success", function()
    local ok, kind, code = shell.execute("exit 0")
    check.is_true(ok == true, "exit 0 must succeed")
    check.same("exit", kind)
    check.same(0, code)
  end)

  it("propagates a non-zero exit code unchanged", function()
    local ok, _, code = shell.execute("exit 42")
    check.is_false(ok == true)
    check.same(42, code)
  end)

  it("distinguishes a missing command 127 from a failing command", function()
    local ok, _, code = shell.execute("missing_command_for_seam_72 >/dev/null 2>&1")
    check.is_false(ok == true)
    check.same(127, code)
  end)

  it("preserves cmd.exe metacharacters and percent text literally", function()
    -- 原生 Lua 的 os.execute 走 cmd.exe,它会把 %PATH% 展开;& | < > ^ ( ) 也是元字符。
    -- 执行缝必须让命令文本逐字节到达 bash。
    local root = require("foundation.env").make_temp_path("seam 中文 space", "")
    local out = root .. "/receipt.txt"
    -- 单引号经 shell_quote 转义(& | < > ^ ( ) % 都留在正文里,由 cmd 元字符面考验)。
    local hazard = [[a'b&c|d<e>f^g%PATH%h(i)j!k "quoted"]]
    fs.ensure_dir(root)
    local ok = shell.execute(
      "printf '%s' " .. shell.shell_quote(hazard) .. " > " .. shell.shell_quote(out))
    local got = fs.read_raw(out)
    fs.remove_path(root)
    check.is_true(ok == true, "hazard body must run under bash")
    check.same(hazard, got, "the seam must not let cmd.exe rewrite the command text")
  end)

  it("keeps single-quote wrapping and env prefix export working", function()
    local command = shell.build_env_lines({ MONOPOLY_SEAM_235 = "value with space 100%" })
      .. " " .. shell.build_command({ "bash", "-c", "printf %s \"$MONOPOLY_SEAM_235\"" })
    local root = require("foundation.env").make_temp_path("seam_env", "")
    local out = root .. "/env.txt"
    fs.ensure_dir(root)
    local ok = shell.execute(command .. " > '" .. out .. "'")
    local got = fs.read_raw(out)
    fs.remove_path(root)
    check.is_true(ok == true)
    check.same("value with space 100%", got)
  end)

  it("reports unavailable with install guidance when bash cannot be found", function()
    local ok, kind, code = shell.execute("exit 0", { bash = "C:/no such place/bash.exe" })
    check.is_false(ok == true)
    check.same("unavailable", kind)
    check.same(3, code)
    local message = shell.bash_unavailable_message()
    check.matches("status=unavailable", message, 1, true)
    check.matches("Git for Windows", message, 1, true)
  end)

  -- #234 F1/F15:执行缝只剩一个实现。capture 形态由同一个 shell.execute 提供,
  -- foundation.bash 上不再有第二个对外执行名(bash.capture)。
  it("capture mode reads back output through the same seam", function()
    local output, ok, code = shell.execute("printf 'cap-ok'", { capture = true })
    check.is_true(ok == true)
    check.same(0, code)
    check.same("cap-ok", output)

    local missing, mok, mcode = shell.execute("exit 0",
      { capture = true, bash = "C:/no such place/bash.exe" })
    check.is_nil(missing)
    check.is_nil(mok)
    check.same(3, mcode)
  end)

  it("foundation.bash exposes no second capture entry", function()
    local bash_lib = require("foundation.bash")
    check.equal("function", type(bash_lib.execute))
    check.is_nil(bash_lib.capture,
      "bash.capture must be gone: shell.execute({capture=true}) is the only seam")
  end)
end)