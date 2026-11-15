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

  -- shell_quote 这个名字被全仓二十多处调用点依赖,引号实现却只该有一份:
  -- 转发到原语叶子,名字与 assert 语义留在原地。结构断言(读源码)而非行为断言——
  -- 两种写法的行为本来就一样,重复只有这里看得出来。
  it("leaves the POSIX escaping body in the primitive leaf", function()
    local source = assert(io.open(shell.__source or "tools/foundation/shell.lua", "rb")):read("*a")
    check.is_nil(source:find([[gsub("'", "']], 1, true),
      "shell.lua must forward to primitives.quote instead of re-escaping single quotes")
    check.truthy(source:find("primitives.quote", 1, true), "shell_quote must forward to primitives.quote")
  end)

  it("quotes through the shared primitive and keeps the assert semantics", function()
    local primitives = require("foundation.primitives")
    for _, value in ipairs({ "", "plain", "a b", "a'b", "中文 路径", "a$b", "a\\b" }) do
      check.equal(primitives.quote(value), shell.shell_quote(value), "quote mismatch: " .. value)
    end
    check.equal("''", shell.shell_quote(nil))
    check.has_error(function() shell.shell_quote("a\nb") end)
    check.has_error(function() shell.shell_quote("a\0b") end)
  end)

  it("foundation.bash exposes no second capture entry", function()
    local bash_lib = require("foundation.bash")
    check.equal("function", type(bash_lib.execute))
    check.is_nil(bash_lib.capture,
      "bash.capture must be gone: shell.execute({capture=true}) is the only seam")
  end)
end)

-- 执行缝把 os/io 原语下沉到 primitives 叶子之后,可观察行为必须逐字节不变;
-- 同时钉住「同一进程里 primitives 只装一次」——装两次会让 unique_name 的计数器分裂,
-- 临时脚本名可能撞车。
describe("shell execute seam consumes the primitives leaf", function()
  local bash_lib = require("foundation.bash")
  local primitives = require("foundation.primitives")

  it("writes temp scripts named eggy_exec_*.sh under the primitives temp dir", function()
    local output, ok, code = shell.execute([[printf '%s' "$0"]], { capture = true })
    check.is_true(ok == true)
    check.same(0, code)
    local dir, name = tostring(output):match("^(.*)/([^/]+)$")
    check.same(primitives.tmp_dir(), dir, "temp scripts must live in primitives.tmp_dir()")
    check.matches("^eggy_exec_.+%.sh$", name)
  end)

  -- 探针脚本原先手拼 \"'\" 包住 marker;临时目录含单引号时那串引号会被 bash 提前闭合,
  -- 探针失败 → 整台机器判「找不到 bash」。改走 primitives.quote 后同一场景必须照常发现。
  it("quotes the probe marker so a temp dir with a quote still discovers bash", function()
    local env = require("foundation.env")
    local root = env.make_temp_path("probe_quote", "")
    local ok, err = xpcall(function()
      local weird = root .. "/sp ace'quote"
      check.truthy(fs.ensure_dir(weird))
      local real_tmp, real_bash_tmp = primitives.tmp_dir, bash_lib.system_tmp_dir
      rawset(primitives, "tmp_dir", function() return weird end)
      rawset(bash_lib, "system_tmp_dir", function() return weird end)
      bash_lib.reset()
      local ran, kind, code = bash_lib.execute("exit 0")
      local reason = bash_lib.last_unavailable()
      rawset(primitives, "tmp_dir", real_tmp)
      rawset(bash_lib, "system_tmp_dir", real_bash_tmp)
      bash_lib.reset()
      check.is_true(ran == true, "bash must stay discoverable: " .. tostring(reason))
      check.same("exit", kind)
      check.same(0, code)
    end, debug.traceback)
    fs.remove_path(root)
    check.is_true(ok, err)
  end)

  -- tools/ 不在搜索面上时,执行缝只能按自身位置 loadfile primitives;那条路径必须把结果
  -- 登记进 package.loaded,否则之后再 require 会得到第二份,计数器各数各的。
  it("loads primitives once so the unique-name counter is not split", function()
    local env = require("foundation.env")
    local proc = require("foundation.proc")
    local lua54 = require("foundation.lua54")
    local repo = env.current_dir()
    local root = env.make_temp_path("primitives_single_load", "")
    local ok, err = xpcall(function()
      check.truthy(fs.ensure_dir(root))
      local script = root .. "/probe.lua"
      check.truthy(fs.write_file(script, table.concat({
        'package.path = "/nonexistent/?.lua"',
        "local bash = assert(loadfile([[" .. repo .. "/tools/foundation/bash.lua]]))()",
        'local out, ok, code = bash.execute([[printf %s "$0"]], { capture = true })',
        "assert(ok == true, tostring(out) .. tostring(code))",
        'package.path = [[' .. repo .. "/?.lua;" .. repo .. '/tools/?.lua]] .. ";" .. package.path',
        'local registered = package.loaded["foundation.primitives"]',
        'local primitives = require("foundation.primitives")',
        'local name = primitives.unique_name("probe", "")',
        'io.write(tostring(out), "\\n", name, "\\n",',
        '  tostring(registered ~= nil and registered == primitives))',
        "",
      }, "\n")))
      local result = proc.run_command({ lua54.lua54_bin(), script }, { cwd = repo })
      check.truthy(result.ok, result.output)
      local lines = {}
      for line in tostring(result.output):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      local script_path, name, registered = lines[1], lines[2], lines[3]
      check.truthy(script_path, result.output)
      check.same("true", registered,
        "the loadfile branch must register primitives in package.loaded")
      local script_name = tostring(script_path):match("([^/]+)$")
      local script_counter = tonumber(script_name:match("^eggy_exec_%d+_(%d+)_"))
      local probe_counter = tonumber(name:match("^probe_%d+_(%d+)_"))
      check.truthy(script_counter and probe_counter, result.output)
      check.same(script_counter + 1, probe_counter,
        "bash and require must share one unique_name counter")
    end, debug.traceback)
    fs.remove_path(root)
    check.is_true(ok, err)
  end)
end)