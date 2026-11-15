---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/ops/test/test_deploy.lua") end
require("test.bootstrap").install_package_paths()

-- deploy.lua(story1 deploy_core)的聚焦单测:纯字符串演算 + 沙箱文件系统行为 +
-- CLI 命令面。行为真源是 deploy.lua(历史来源 deploy.ps1,已随 #384 删除,ADR 0030)。
local check = require("luassert")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local proc_lib = require("foundation.proc")
local deploy = require("tools.packages.ops.deploy")

local function _with_stubbed(field, value, fn)
  local original = deploy[field]
  deploy[field] = value
  local ok, err = xpcall(function()
    fn()
  end, debug.traceback)
  deploy[field] = original
  if not ok then
    error(err)
  end
end

local function _with_sandbox(fn)
  local root = env_lib.make_temp_path("deploy_core_spec_中文 空格_", "")
  fs_lib.remove_path(root)
  local ok, err = xpcall(function()
    fn(root)
  end, debug.traceback)
  fs_lib.remove_path(root)
  if not ok then
    error(err)
  end
end

local function _write_file(path, content)
  local ok, err = fs_lib.write_file(path, content)
  if not ok then
    error(err)
  end
end

-- 沙箱项目:含隐藏 Lua、隐藏目录、非 Lua、
-- 缩进注释、行内注释、空行。源侧统计期望:Lua Files 7 / Effective LOC 9。
local function _make_project(root)
  local proj = root .. "/project"
  fs_lib.ensure_dir(proj .. "/src/sub")
  fs_lib.ensure_dir(proj .. "/src/.hiddendir")
  fs_lib.ensure_dir(proj .. "/Data")
  fs_lib.ensure_dir(proj .. "/tools")
  _write_file(proj .. "/main.lua", "-- main\nprint(\"hello\")\n")
  _write_file(proj .. "/src/a.lua", "-- header\nlocal a = 1\n\n  -- indented\nlocal b = 2 -- trailing\n")
  _write_file(proj .. "/src/sub/b.lua", "-- b\nlocal x = 1\nlocal y = 2\n")
  _write_file(proj .. "/src/.hidden.lua", "-- hidden\nlocal h = 1\n")
  _write_file(proj .. "/src/.hiddendir/x.lua", "-- x\nlocal xv = 1\n")
  _write_file(proj .. "/src/notes.txt", "not lua\n")
  _write_file(proj .. "/src/.keep", "keep\n")
  _write_file(proj .. "/Data/UIManagerNodes.lua", "-- nodes\nreturn {}\n")
  _write_file(proj .. "/Data/Prefab.lua", "-- prefab\nreturn {}\n")
  _write_file(proj .. "/tools/placeholder.txt", "placeholder\n")
  return proj
end

describe("deploy public sandbox contracts", function()

it("Lua source directory name is retained", function()
  -- "大富翁" = U+5927 U+5BCC U+7FC1(UTF-8)。
  check.equal("LuaSource_大富翁", deploy.join_lua_source_dir_name())
end)

it("blank path returns empty", function()
  check.equal("", deploy.resolve_normalized_path(""))
  check.equal("", deploy.resolve_normalized_path(nil))
  check.equal("", deploy.resolve_normalized_path("   "))
end)

it("keeps absolute path and trims trailing slashes", function()
  -- 内部路径口径是原生 Windows 正斜杠绝对路径(ADR 0083):C:/Users/... 不再换算成 /mnt/c/...
  check.equal("C:/Users/foo", deploy.resolve_normalized_path("C:/Users/foo/"))
  check.equal("C:/Users/foo", deploy.resolve_normalized_path("C:/Users/foo"))
  check.equal("C:/Users/foo", deploy.resolve_normalized_path("C:\\Users\\foo\\"))
end)

it("relative path is joined to cwd", function()
  local cwd = env_lib.current_dir()
  check.equal(cwd .. "/src", deploy.resolve_normalized_path("src"))
end)

it("tilde expands against home", function()
  _with_stubbed("resolve_home_dir", function()
    return "C:/Users/alice"
  end, function()
    check.equal("C:/Users/alice/Desktop", deploy.resolve_normalized_path("~/Desktop"))
  end)
end)

it("folds dot and dotdot segments", function()
  check.equal("C:/Users/alice/bob", deploy.resolve_normalized_path("C:/Users/alice/sub/../bob"))
  check.equal("C:/Users/alice/sub/bob", deploy.resolve_normalized_path("C:/Users/alice/sub/./bob"))
end)

-- %USERPROFILE% 只在 cmd 内展开;Lua 侧路径里的 %NAME% 是普通字符(#222)。
it("keeps percent text literal", function()
  check.equal("C:/Users/a%HOME%b/x", deploy.resolve_normalized_path("C:/Users/a%HOME%b/x/"))
end)

it("platform name returns win when robocopy is present", function()
  _with_stubbed("detect_native_tools", function()
    return {}
  end, function()
    check.equal("win", deploy.resolve_platform_name())
  end)
end)

-- 不可用退 3:环境问题不能被当成部署失败。resolve_platform_name 直接 os.exit,
-- 所以用例在子进程里跑,只断言退出码与 stderr 状态词。
it("platform name exits 3 with status=unavailable without robocopy", function()
  local root = env_lib.make_temp_path("deploy_native_tools_spec", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(root))
  local driver = root .. "/driver.lua"
  check.is_true(fs_lib.write_file(driver, table.concat({
    "package.path = " .. string.format("%q", env_lib.current_dir() .. "/?.lua;" .. env_lib.current_dir() .. "/tools/?.lua;")
      .. " .. package.path",
    "local deploy = require('tools.packages.ops.deploy')",
    "deploy.detect_native_tools = function() return { 'robocopy' } end",
    "deploy.resolve_platform_name()",
    "",
  }, "\n")))
  local result = proc_lib.run_command({ require("foundation.lua54").lua54_bin(), driver })
  fs_lib.remove_path(root)
  check.same(3, result.code, result.output)
  check.truthy(result.output:find("status=unavailable", 1, true), result.output)
  check.truthy(result.output:find("robocopy", 1, true), result.output)
end)

-- 家目录解析只读原生环境变量与一条 cmd 兜底,不经 wslpath、不经 /mnt/c(ADR 0083 第 5 条)。
it("home directory comes from the native USERPROFILE", function()
  local commands = {}
  local home = deploy.resolve_windows_home_dir(function(command)
    commands[#commands + 1] = command
    return "C:\\Users\\测试 user\r\n"
  end, function(name)
    return name == "USERPROFILE" and "C:\\Users\\测试 user" or nil
  end)
  check.same("C:/Users/测试 user", home)
  check.same(0, #commands, "USERPROFILE 存在时不得起任何子进程")
end)

it("home directory normalizes backslashes and trailing separators", function()
  check.same("C:/Users/foo", deploy.resolve_windows_home_dir(nil, function()
    return "C:\\Users\\foo\\"
  end))
end)

it("home directory falls back to cmd when USERPROFILE is missing", function()
  local commands = {}
  local home = deploy.resolve_windows_home_dir(function(command)
    commands[#commands + 1] = command
    return "C:\\Users\\fallback\r\n"
  end, function()
    return nil
  end)
  check.same("C:/Users/fallback", home)
  check.same(1, #commands)
  check.same("cmd /c echo %USERPROFILE%", commands[1])
  check.is_nil(commands[1]:find("/mnt/c", 1, true), "兜底不得经 /mnt/c")
  check.is_nil(commands[1]:find("wslpath", 1, true), "兜底不得经 wslpath")
end)

it("home directory is empty when the profile cannot be resolved", function()
  check.same("", deploy.resolve_windows_home_dir(function() return "" end, function() return nil end))
  check.same("", deploy.resolve_windows_home_dir(function() return "not a drive path\n" end, function() return nil end))
end)

-- MONOPOLY_DEPLOY_HOME 是保留的覆写面:设了就不读 USERPROFILE、不起 cmd。
it("home directory honours the explicit override", function()
  local home = deploy.resolve_home_dir(function(name)
    if name == "MONOPOLY_DEPLOY_HOME" then return "D:\\sandbox\\home" end
    error("override must win over USERPROFILE")
  end)
  check.same("D:/sandbox/home", home)
end)

-- 部署按工作树原样拷贝(插桩通道依赖这一点),所以只提示 payload 里未提交的文件。
it("uncommitted payload lists porcelain paths scoped to the deploy payload", function()
  local commands = {}
  local paths = deploy.list_uncommitted_payload("/repo root", function(command)
    commands[#commands + 1] = command
    return " M src/ui/a.lua\0?? src/新 文件.lua\0R  src/new.lua\0src/old.lua\0 M Data/Prefab.lua\0"
  end)
  check.same({ "src/ui/a.lua", "src/新 文件.lua", "src/new.lua", "Data/Prefab.lua" }, paths)
  check.truthy(commands[1]:find("git -C '/repo root' -c core.quotepath=false status --porcelain -z", 1, true),
    commands[1])
  check.truthy(commands[1]:find("-- src main.lua Data/UIManagerNodes.lua Data/Prefab.lua", 1, true), commands[1])
end)

it("uncommitted payload is empty for a clean tree or when git is unavailable", function()
  check.same({}, deploy.list_uncommitted_payload("/repo", function() return "" end))
end)

it("uncommitted payload notice caps the listing and reports the total", function()
  local paths = {}
  for i = 1, 12 do paths[i] = "src/f" .. i .. ".lua" end
  local lines = deploy.format_uncommitted_notice(paths)
  check.same("WARNING: 12 uncommitted payload file(s) deployed as-is (working tree, not HEAD):", lines[1])
  check.same("  src/f1.lua", lines[2])
  check.same("  src/f10.lua", lines[11])
  check.same("  ... and 2 more", lines[12])
  check.same(12, #lines)
  check.same({}, deploy.format_uncommitted_notice({}))
end)

it("project root is true for full project shape", function()
  _with_sandbox(function(root)
    local proj = _make_project(root)
    check.is_true(deploy.test_project_root(proj))
  end)
end)

it("project root is false when marker missing", function()
  _with_sandbox(function(root)
    local proj = _make_project(root)
    check.is_false(deploy.test_project_root(proj .. "/tools"))
    check.is_false(deploy.test_project_root(root))
  end)
end)

it("line count skips blank and full line comments", function()
  _with_sandbox(function(root)
    local sample = root .. "/sample.lua"
    _write_file(sample, "-- a\nlocal x = 1\n\n")
    check.equal(1, deploy.get_effective_lua_line_count_for_file(sample))
    _write_file(sample, "-- only comment\n")
    check.equal(0, deploy.get_effective_lua_line_count_for_file(sample))
    _write_file(sample, "")
    check.equal(0, deploy.get_effective_lua_line_count_for_file(sample))
  end)
end)

-- #527:块注释内部行(典型:每文件尾部的 mutate4lua manifest)不得计为有效代码。
it("line count skips block comment interior", function()
  _with_sandbox(function(root)
    local sample = root .. "/sample.lua"
    _write_file(sample, "local a = 1\n--[[ mutate4lua-manifest\nscope.1.id=function:x\nscope.1.startLine=1\n]]\nlocal b = 2\n")
    check.equal(2, deploy.get_effective_lua_line_count_for_file(sample))
    -- 长括号等级形式 --[==[ ... ]==]
    _write_file(sample, "--[==[\ninterior line\n]==]\nlocal c = 3\n")
    check.equal(1, deploy.get_effective_lua_line_count_for_file(sample))
  end)
end)

it("line count handles inline block close and trailing code", function()
  _with_sandbox(function(root)
    local sample = root .. "/sample.lua"
    -- 同行闭合的行首块注释,余下代码仍计
    _write_file(sample, "--[[@meta]] local x = 1\n")
    check.equal(1, deploy.get_effective_lua_line_count_for_file(sample))
    -- 块注释闭合行尾部带代码仍计
    _write_file(sample, "--[[\ninterior\n]] local y = 2\n")
    check.equal(1, deploy.get_effective_lua_line_count_for_file(sample))
    -- 行内注释(--[[@as T]] 在行尾,行首为代码)行为不变
    _write_file(sample, "local z = f() --[[@as T]]\n")
    check.equal(1, deploy.get_effective_lua_line_count_for_file(sample))
  end)
end)

it("line count for missing file is zero", function()
  check.equal(0, deploy.get_effective_lua_line_count_for_file("/nonexistent/deploy_core_spec.lua"))
end)

it("line count for directory includes hidden files", function()
  _with_sandbox(function(root)
    local proj = _make_project(root)
    check.equal(6, deploy.get_effective_lua_line_count_for_dir(proj .. "/src"))
    check.equal(0, deploy.get_effective_lua_line_count_for_dir(proj .. "/nonexistent"))
  end)
end)

it("Lua file count includes recursive Lua files only", function()
  _with_sandbox(function(root)
    local proj = _make_project(root)
    check.equal(4, deploy.get_lua_file_count(proj .. "/src"))
    check.equal(1, deploy.get_lua_file_count(proj .. "/main.lua"))
    check.equal(0, deploy.get_lua_file_count(proj .. "/nonexistent"))
  end)
end)

it("copy file creates parent and overwrites", function()
  _with_sandbox(function(root)
    local source = root .. "/src.txt"
    _write_file(source, "hello")
    local target = root .. "/nested/dir/dst.txt"
    check.is_true(deploy.copy_file_with_parent_dir(source, target))
    check.equal("hello", fs_lib.read_raw(target))
    _write_file(source, "updated")
    check.is_true(deploy.copy_file_with_parent_dir(source, target))
    check.equal("updated", fs_lib.read_raw(target))
  end)
end)

it("copy file errors on missing source", function()
  _with_sandbox(function(root)
    check.has_error(function()
      deploy.copy_file_with_parent_dir(root .. "/missing.lua", root .. "/out/dst.lua")
    end)
  end)
end)

it("copy file errors when target is directory", function()
  _with_sandbox(function(root)
    local source = root .. "/src.txt"
    _write_file(source, "hello")
    local target_dir = root .. "/outdir"
    fs_lib.ensure_dir(target_dir)
    check.has_error(function()
      deploy.copy_file_with_parent_dir(source, target_dir)
    end)
  end)
end)

it("reset directory clears and recreates", function()
  _with_sandbox(function(root)
    local dir = root .. "/reset"
    fs_lib.ensure_dir(dir .. "/sub")
    _write_file(dir .. "/sub/stale.lua", "stale")
    deploy.reset_directory(dir)
    check.is_true(fs_lib.path_exists(dir))
    check.is_false(fs_lib.path_exists(dir .. "/sub/stale.lua"))
  end)
end)

-- 目录镜像交给原生 robocopy /MIR:镜像语义(目标侧陈旧项消失、源侧隐藏项与空目录
-- 保留)由 robocopy 保证,这里钉命令形态与退出码判定,不真跑 robocopy(测试注入桩)。
it("copy tree delegates the mirror to native robocopy", function()
  _with_sandbox(function(root)
    local proj = _make_project(root)
    local target = root .. "/target/src"
    local commands = {}
    _with_stubbed("run_robocopy", function(command)
      commands[#commands + 1] = command
      return 1
    end, function()
      check.is_true(deploy.copy_directory_tree(proj .. "/src", target))
    end)
    check.same(1, #commands)
    local command = commands[1]
    check.truthy(command:find("robocopy", 1, true), command)
    check.truthy(command:find("/MIR", 1, true), command)
    check.truthy(command:find("'" .. proj .. "/src'", 1, true), command)
    check.truthy(command:find("'" .. target .. "'", 1, true), command)
    check.is_nil(command:find("cp -R", 1, true), "不得回落到 cp -R")
    check.is_nil(command:find("wslpath", 1, true), command)
  end)
end)

-- robocopy 的 0..7 都是成功(0 无变化 / 1 有拷贝 / 2 有额外项被清 / 3 两者都有);
-- 8 起才是失败。按 0/非 0 判定会把正常部署读成失败。
it("robocopy exit codes 0..7 are success and 8+ are failures", function()
  for code = 0, 7 do
    check.is_true(deploy.robocopy_succeeded(code), "exit " .. code .. " must be success")
  end
  for _, code in ipairs({ 8, 9, 16, 17 }) do
    check.is_false(deploy.robocopy_succeeded(code), "exit " .. code .. " must be failure")
  end
  check.is_false(deploy.robocopy_succeeded(nil))
end)

it("copy tree errors when robocopy reports a fatal exit code", function()
  _with_sandbox(function(root)
    local proj = _make_project(root)
    _with_stubbed("run_robocopy", function()
      return 16
    end, function()
      check.has_error(function()
        deploy.copy_directory_tree(proj .. "/src", root .. "/target/src")
      end)
    end)
  end)
end)

it("copy tree errors on missing source", function()
  _with_sandbox(function(root)
    check.has_error(function()
      deploy.copy_directory_tree(root .. "/missing", root .. "/target")
    end)
  end)
end)

local function _run_deploy_lua(extra_args)
  local args = { require("foundation.lua54").lua54_bin(), "tools/packages/ops/deploy.lua" }
  for _, value in ipairs(extra_args or {}) do
    args[#args + 1] = value
  end
  return proc_lib.run_command(args, {
    cwd = env_lib.current_dir(),
  })
end

-- 经 tools/cli.lua 的子命令入口(壳 tools/packages/ops/cli.lua 转发)。
-- 只测 --help 与多余参数:两者都在部署动作前结束,不会真拷部署目录。
local function _run_cli_deploy(extra_args)
  local args = { require("foundation.lua54").lua54_bin(), "tools/cli.lua", "deploy" }
  for _, value in ipairs(extra_args or {}) do
    args[#args + 1] = value
  end
  return proc_lib.run_command(args, {
    cwd = env_lib.current_dir(),
  })
end

it("script rejects extra positional arguments", function()
  local result = _run_deploy_lua({ "extra1", "extra2" })
  check.is_false(result.ok)
  check.truthy(result.output:find("ERROR:", 1, true),
    "extra args must fail with ERROR on stderr: " .. result.output)
end)

it("script rejects help without usage text", function()
  local result = _run_deploy_lua({ "--help" })
  check.is_false(result.ok)
  check.truthy(result.output:find("ERROR:", 1, true),
    "--help must fail with ERROR on stderr: " .. result.output)
  check.is_nil(result.output:find("Usage", 1, true),
    "--help must not print usage text: " .. result.output)
  check.is_nil(result.output:find("用法", 1, true),
    "--help must not print Chinese usage text: " .. result.output)
end)

it("CLI subcommand help shows usage", function()
  local result = _run_cli_deploy({ "--help" })
  check.is_true(result.ok, "deploy --help via cli.lua must exit 0: " .. result.output)
  check.truthy(result.output:find("用法", 1, true) ~= nil,
    "deploy --help via cli.lua must show Chinese usage: " .. result.output)
end)

it("CLI subcommand help states the target rule and points to deploy-diff", function()
  local result = _run_cli_deploy({ "--help" })
  check.is_true(result.ok, result.output)
  check.truthy(result.output:find("Desktop/dev/eggy/LuaSource_大富翁", 1, true), result.output)
  check.truthy(result.output:find("MONOPOLY_DEPLOY_HOME", 1, true), result.output)
  check.truthy(result.output:find("deploy-diff", 1, true), result.output)
end)

it("CLI forwards extra arguments to script", function()
  local result = _run_cli_deploy({ "额外 参数" })
  check.is_false(result.ok)
  check.truthy(result.output:find("ERROR:", 1, true),
    "extra args via cli.lua must reach deploy.lua and fail with ERROR: " .. result.output)
end)
end)
