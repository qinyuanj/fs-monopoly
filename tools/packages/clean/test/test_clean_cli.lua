---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/clean/test/test_clean_cli.lua") end

require("test.bootstrap").install_package_paths()

-- clean / distclean 的原生 Windows 窄反馈(#69 / ADR 0066)。清单与旧 Makefile 同口径:
-- 仓根的 build/ tmp/ 整树删,luacov 的
-- stats/report 残留(含 luacov.<名>.stats.out 一类)删文件,未命中静默忽略;
-- 项目工具缓存退役后 clean 与 distclean 同义,都不碰非清单目录。
--
-- 只在临时目录里跑:env.repo_root 指向夹具根,绝不对真实仓库执行清理。
local check = require("luassert")
local clean_cli = require("packages.clean.cli")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local shell_lib = require("foundation.shell")

local TARGET_FILES = {
  "luacov.stats.out",
  "luacov.report.out",
  "luacov.spec_lane.stats.out",
  "luacov.uml.report.out",
}

-- 名字像但不在清单里:不能被顺手删掉。
local KEPT_FILES = {
  "luacov.lua",
  "luacov.stats.out.bak",
  "my.luacov.stats.out",
  "notes.txt",
  "src/main.lua",
  "src/build/keep.lua",
  "src/luacov.stats.out",
}

local TARGET_DIRS = { "build", "tmp" }

local function _with_fixture(fn)
  local root = env_lib.make_temp_path("clean_cli_spec", "")
  fs_lib.remove_path(root)
  local ok, err = xpcall(function()
    for _, name in ipairs(TARGET_FILES) do
      check.is_true(fs_lib.write_file(path_lib.join_path(root, name), "x\n"))
    end
    for _, name in ipairs(KEPT_FILES) do
      check.is_true(fs_lib.write_file(path_lib.join_path(root, name), "x\n"))
    end
    for _, dir in ipairs(TARGET_DIRS) do
      check.is_true(fs_lib.write_file(path_lib.join_path(root, dir .. "/nested/artifact.txt"), "x\n"))
    end
    check.is_true(fs_lib.write_file(path_lib.join_path(root, ".local-cache/manifest"), "x\n"))
    fn(root)
  end, debug.traceback)
  fs_lib.remove_path(root)
  if not ok then
    error(err)
  end
end

local function _assert_cleaned(root)
  for _, name in ipairs(TARGET_FILES) do
    check.is_false(fs_lib.path_exists(path_lib.join_path(root, name)), "应已删除: " .. name)
  end
  for _, dir in ipairs(TARGET_DIRS) do
    check.is_false(fs_lib.path_exists(path_lib.join_path(root, dir)), "应已删除: " .. dir)
  end
  for _, name in ipairs(KEPT_FILES) do
    check.is_true(fs_lib.path_exists(path_lib.join_path(root, name)), "不该删除: " .. name)
  end
end

describe("clean cli", function()

it("clean removes the listed artifacts and keeps unrelated directories", function()
  _with_fixture(function(root)
    check.equal(0, clean_cli.main({}, { repo_root = root, action = "clean" }))

    _assert_cleaned(root)
    check.is_true(fs_lib.path_exists(path_lib.join_path(root, ".local-cache/manifest")),
      "clean 不碰清单外目录")
  end)
end)

it("distclean is the same cleanup as clean", function()
  _with_fixture(function(root)
    check.equal(0, clean_cli.main({}, { repo_root = root, action = "distclean" }))

    _assert_cleaned(root)
    check.is_true(fs_lib.path_exists(path_lib.join_path(root, ".local-cache/manifest")),
      "distclean 不碰清单外目录")
  end)
end)

-- 受支持环境只有 Lua 与 cmd.exe(ADR 0066):开发机 PATH 上碰巧有 Git 的 usr/bin
-- 时 `rm` 也能跑通,这条用例把子进程 PATH 收窄到 Lua 所在目录 + Windows 系统目录,
-- 钉住清理不依赖任何 POSIX 工具。
local function _native_only_path()
  local where = proc_lib.run_command("where lua")
  check.is_true(where.ok, where.output)
  local lua_path = path_lib.normalize_path((where.output:match("^[^\r\n]+")))
  local system_root = assert(os.getenv("SystemRoot"), "SystemRoot 未设置")
  return table.concat({
    path_lib.parent_dir(lua_path):gsub("/", "\\"),
    system_root .. "\\System32",
    system_root,
  }, ";")
end

it("clean works with only lua and cmd.exe on PATH", function()
  _with_fixture(function(root)
    local driver = path_lib.join_path(root, "clean_driver.lua")
    check.is_true(fs_lib.write_file(driver, table.concat({
      "package.path = './?.lua;' .. package.path",
      "require('test.bootstrap').install_package_paths()",
      "os.exit(require('packages.clean.cli').main({}, { repo_root = arg[1], action = 'distclean' }))",
      "",
    }, "\n")))
    local command = 'set "PATH=' .. _native_only_path() .. '" & lua '
      .. shell_lib.shell_quote(driver:gsub("/", "\\")) .. " "
      .. shell_lib.shell_quote(root:gsub("/", "\\"))
    local result = proc_lib.run_command(command, { cwd = env_lib.current_dir() })

    check.equal(0, result.code, result.output)
    _assert_cleaned(root)
    check.is_true(fs_lib.path_exists(path_lib.join_path(root, ".local-cache/manifest")), result.output)
  end)
end)

it("an already clean tree is a quiet success", function()
  local root = env_lib.make_temp_path("clean_cli_empty", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(root))
  local ok, err = xpcall(function()
    check.equal(0, clean_cli.main({}, { repo_root = root, action = "clean" }))
    check.is_true(fs_lib.is_dir(root))
  end, debug.traceback)
  fs_lib.remove_path(root)
  if not ok then
    error(err)
  end
end)

it("unknown arguments are a usage error and touch nothing", function()
  _with_fixture(function(root)
    check.equal(2, clean_cli.main({ "--bogus" }, { repo_root = root, action = "clean" }))
    check.is_true(fs_lib.path_exists(path_lib.join_path(root, "luacov.stats.out")))
    check.is_true(fs_lib.is_dir(path_lib.join_path(root, "build")))
  end)
end)

end)
