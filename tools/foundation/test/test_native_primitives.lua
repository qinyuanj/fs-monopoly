-- 原生 Windows 公共原语的回归(ADR 0083 / #235);也可用 Lua 直接跑。
package.path = package.path .. ";./tools/?.lua"
local runtime = dofile("tools/foundation/runtime_path_ops.lua")
local env = require("foundation.env")
local fs = require("foundation.fs")
local proc = require("foundation.proc")
local path = require("foundation.path")
local shell = require("foundation.shell")
local lua54 = require("foundation.lua54")
require("test.bootstrap").install_package_paths()
local check = require("luassert")

describe("native primitives", function()
  local saved_cpath
  before_each(function() saved_cpath = package.cpath end)
  after_each(function() package.cpath = saved_cpath end)

-- 内部路径口径(ADR 0083):D:/… / C:/… 正斜杠 Windows 绝对路径。
it("real cwd is an absolute Windows path", function()
  local cwd = runtime.current_dir()
  check.matches("^%a:/", cwd, "cwd must be an absolute Windows path: " .. cwd)
  check.equal(cwd, env.current_dir(), "bootstrap and process cwd must agree")
  check.is_true(runtime.path_exists(cwd .. "/tools/cli.lua"), "cwd must load the real project")
end)

it("stale inherited PWD does not override the real working directory", function()
  -- 子进程用 cwd= 起时只改真实 cwd,不更新继承来的 PWD;current_dir 必须以真实 cwd 为准,
  -- 否则嵌套 runner 会把仓根当 worker。
  local root = env.make_temp_path("stale_pwd", "")
  local ok, err = xpcall(function()
    check.truthy(fs.ensure_dir(root))
    local script = root .. "/probe.lua"
    check.truthy(fs.write_file(script, [[
local root = "]] .. env.current_dir() .. [["
package.path = root .. "/?.lua;" .. root .. "/tools/?.lua;" .. package.path
io.write(require("foundation.env").current_dir())
]]))
    local result = proc.run_command(
      { lua54.lua54_bin(), script },
      { cwd = root, env = { PWD = path.resolve_path(root, "..") } })
    check.truthy(result.ok, result.output)
    check.equal(path.resolve_path(root, "."), result.output)
  end, debug.traceback)
  check.truthy(fs.remove_path(root))
  check.is_true(ok, err)
end)

it("native files round trip discover copy and remove", function()
  local root = env.make_temp_path("native_中文 space", "")
  local ok, err = xpcall(function()
    check.truthy(fs.write_file(root .. "/source/子目录/a.lua", "hello\0中文!"))
    check.truthy(fs.ensure_dir(root .. "/source/empty"))
    check.truthy(fs.ensure_dir(root .. "/src"))
    check.truthy(fs.ensure_dir(root .. "/test"))
    check.truthy(fs.write_file(root .. "/tools/cli.lua", "return {}"))
    local bootstrap = dofile("tools/foundation/bootstrap.lua")
    check.equal(root, bootstrap.resolve(root .. "/tools/probe.lua").repo_root)
    check.truthy(fs.copy_tree(root .. "/source", root .. "/copy"))
    check.truthy(fs.is_dir(root .. "/copy/empty"))
    check.truthy(fs.read_file(root .. "/copy/子目录/a.lua") == "hello\0中文!")
    local files = assert(proc.collect_lua_files(root .. "/copy"))
    check.same({ root .. "/copy/子目录/a.lua" }, files)
    check.truthy(fs.copy_file(files[1], root .. "/binary copy.lua"))
    check.truthy(fs.read_file(root .. "/binary copy.lua") == "hello\0中文!")
  end, debug.traceback)
  check.truthy(fs.remove_path(root))
  check.truthy(not fs.path_exists(root))
  check.is_true(ok, err)
end)

it("ensure_dir on an existing directory spawns no shell; a file path still fails", function()
  local root = env.make_temp_path("native_ensure_dir", "")
  local real_execute = shell.execute
  local spawned = {}
  local ok, err = xpcall(function()
    check.truthy(fs.write_file(root .. "/sub/file.txt", "x"))
    rawset(shell, "execute", function(command) spawned[#spawned + 1] = command; return real_execute(command) end)
    check.is_true(fs.ensure_dir(root .. "/sub"))
    check.truthy(fs.write_file(root .. "/sub/again.txt", "y"))
    -- lint-allow: call-count 已有目录不起 mkdir 子进程是 write_file/copy_file 的性能契约
    check.same({}, spawned)
    check.is_nil(fs.ensure_dir(root .. "/sub/file.txt"))
    check.truthy(fs.ensure_dir(root .. "/sub/new/deeper"))
    check.is_true(fs.is_dir(root .. "/sub/new/deeper"))
  end, debug.traceback)
  rawset(shell, "execute", real_execute)
  check.truthy(fs.remove_path(root))
  check.is_true(ok, err)
end)

-- #234 F7:is_dir / path_exists 只读、无副作用——旧实现会在目标目录里建探针文件再删,
-- deploy-diff 因此在实际部署目录里写了东西。这里钉住:多次判定后目录内容逐项不变。
it("is_dir and path_exists leave the directory unchanged", function()
  local root = env.make_temp_path("fs_probe_no_side_effect", "")
  local ok, err = xpcall(function()
    check.truthy(fs.ensure_dir(root .. "/inner"))
    check.truthy(fs.write_file(root .. "/inner/a.lua", "x"))
    local before = proc.collect_files(root .. "/inner")

    check.is_true(fs.is_dir(root .. "/inner"))
    check.is_true(fs.path_exists(root .. "/inner"))
    check.is_true(fs.path_exists(root .. "/inner/a.lua"))
    check.is_false(fs.is_dir(root .. "/inner/a.lua"))
    check.is_false(fs.is_dir(root .. "/inner/nope"))
    check.is_false(fs.path_exists(root .. "/inner/nope"))
    -- 与 fs 同源、bootstrap 用的 runtime_path_ops 判定同样不写文件。
    check.same("dir", runtime.probe_path(root .. "/inner"))
    check.same("file", runtime.probe_path(root .. "/inner/a.lua"))
    check.same("missing", runtime.probe_path(root .. "/inner/nope"))

    check.same(before, proc.collect_files(root .. "/inner"),
      "probing must not create or delete any file inside the directory")
  end, debug.traceback)
  check.truthy(fs.remove_path(root))
  check.is_true(ok, err)
end)

it("run_command env option exports variables to the child", function()
  local result = proc.run_command(
    { lua54.lua54_bin(), "-e", 'io.write(os.getenv("MONOPOLY_TEST_ENV_124") or "missing")' },
    { env = { MONOPOLY_TEST_ENV_124 = "value with space 100%" } })
  check.is_true(result.ok)
  check.same("value with space 100%", result.output)
end)

it("real process arguments output exit and stdin", function()
  local root = env.make_temp_path("process_中文 space", "")
  local ok, err = xpcall(function()
    local script = root .. "/probe.lua"
    check.truthy(fs.write_file(script, [[
for i = 1, #arg do io.write(arg[i], "\n") end
io.write(io.read("*a"))
io.stdout:flush()
io.stderr:write("stderr\n")
os.exit(7)
]]))
    check.truthy(fs.write_file(root .. "/input.txt", "stdin\n"))
    local result = proc.run_command({ lua54.lua54_bin(), script, "", "中文 space", 'quote"and&pipe|', "%PATH%", "bang!caret^", "tail\\" }, { cwd = root, stdin_path = root .. "/input.txt" })
    check.truthy(not result.ok and result.code == 7, "real exit 7 must be preserved: " .. result.output)
    check.truthy(result.output:gsub("\r\n", "\n") == '\n中文 space\nquote"and&pipe|\n%PATH%\nbang!caret^\ntail\\\nstdin\nstderr\n', result.output)
    check.is_true(proc.command_exists(lua54.lua54_bin()))
    check.truthy(not proc.command_exists("missing_native_command_72"))
    local missing = proc.run_command({ "missing_native_command_72" })
    check.truthy(not missing.ok and missing.code ~= 0 and missing.output ~= "")
    local success = proc.run_command({ lua54.lua54_bin(), "-e", 'io.write("ok")' })
    check.is_true(success.ok and success.code == 0 and success.output == "ok", success.output)
  end, debug.traceback)
  check.truthy(fs.remove_path(root))
  check.is_true(ok, err)
end)

it("empty discovery and native CLI startup", function()
  local root = env.make_temp_path("empty_中文 space", "")
  check.truthy(fs.ensure_dir(root))
  local files, err = proc.collect_lua_files(root)
  check.truthy(fs.remove_path(root))
  check.truthy(files and #files == 0, err)
  local result = proc.run_command({ lua54.lua54_bin(), "tools/cli.lua", "spec-lane", "--help" })
  check.truthy(result.ok and result.code == 0, result.output)
  check.truthy(result.output:find("profile", 1, true), result.output)
end)

it("controlled lua environment exposes native shared modules", function()
  local original = package.cpath
  require("foundation.lua_env").install_paths({ "C:/opt/controlled/tree" })
  local cpath = package.cpath
  package.cpath = original
  check.truthy(cpath:find("C:/opt/controlled/tree/lib/lua/5.4/?.dll", 1, true))
end)

it("verify forwards native flags without literal quotes", function()
  local result = proc.run_command({ lua54.lua54_bin(), "tools/cli.lua", "verify", "--ticket73-unknown" })
  check.truthy(result.code == 2, result.output)
  check.truthy(result.output:find("unknown flag: --ticket73-unknown", 1, true), result.output)
end)

-- 路径口径(ADR 0083):盘符是绝对路径;MSYS 形态不是内部口径。
it("Windows path shapes and string command", function()
  check.equal("C:/中文 space/file.lua", path.resolve_path("C:/中文 space/root", "../file.lua"))
  check.is_true(path.is_absolute_path("C:/x"))
  check.is_true(path.is_absolute_path("D:/x"))
  check.is_false(path.is_absolute_path("C:x"))
  check.is_true(runtime.is_absolute("C:/x"))
  check.is_false(runtime.is_absolute("relative/x"))
  -- 盘符是绝对路径:绝对目标不再拼到基路径后面。
  check.equal("C:/x", path.resolve_path("C:/base", "C:/x"))
  check.equal("C:/x", runtime.resolve_source_path("@C:/x", "C:/base"))
  local root = env.make_temp_path("shell_中文 space", "")
  check.truthy(fs.ensure_dir(root))
  local command = shell.wrap_command_with_cwd(shell.build_command({ lua54.lua54_bin(), "-e", 'io.write("中文 ok")' }), root)
  local result = proc.run_command(command)
  check.truthy(fs.remove_path(root))
  check.truthy(result.ok and result.output == "中文 ok", result.output)
end)
end)