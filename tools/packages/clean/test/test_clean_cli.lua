---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/clean/test/test_clean_cli.lua") end

require("test.bootstrap").install_package_paths()

-- clean 的 WSL 窄反馈(#69 / ADR 0073)。清单与旧 Makefile 同口径:
-- 仓根的 build/ tmp/ 整树删,luacov 的
-- stats/report 残留(含 luacov.<名>.stats.out 一类)删文件,未命中静默忽略;
-- 不碰非清单目录。
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
    check.equal(0, clean_cli.main({}, { repo_root = root }))

    _assert_cleaned(root)
    check.is_true(fs_lib.path_exists(path_lib.join_path(root, ".local-cache/manifest")),
      "clean 不碰清单外目录")
  end)
end)

-- distclean 别名已删(#220):顶层 --help 只列 clean,distclean 按未知子命令退 2。
it("top-level help lists clean and no longer offers distclean", function()
  local lua_bin = shell_lib.shell_quote(require("foundation.lua54").lua54_bin())
  local help = proc_lib.run_command(lua_bin .. " tools/cli.lua --help", { cwd = env_lib.current_dir() })
  check.equal(0, help.code, help.output)
  check.truthy(help.output:find("\n  clean ", 1, true), help.output)
  check.is_nil(help.output:find("distclean", 1, true), help.output)

  local alias = proc_lib.run_command(lua_bin .. " tools/cli.lua distclean 2>&1", { cwd = env_lib.current_dir() })
  check.equal(2, alias.code, alias.output)
  check.truthy(alias.output:find("未知子命令: distclean", 1, true), alias.output)
end)

-- 受支持环境是 WSL Ubuntu(ADR 0073):清理只依赖 sh 内建与 coreutils 基本命令。
-- 这条用例把子进程 PATH 收窄到解释器所在目录与 /usr/bin:/bin,钉住清理不依赖
-- 任何项目内工具树或额外 PATH 条目。
local function _system_path()
  local lua_bin = require("foundation.lua54").lua54_bin()
  local where = proc_lib.run_command("command -v " .. shell_lib.shell_quote(lua_bin))
  check.is_true(where.ok, where.output)
  local resolved = path_lib.normalize_path((where.output:match("^[^\r\n]+")))
  return table.concat({ path_lib.parent_dir(resolved), "/usr/bin", "/bin" }, ":")
end

it("clean works with only the interpreter and system directories on PATH", function()
  _with_fixture(function(root)
    local driver = path_lib.join_path(root, "clean_driver.lua")
    check.is_true(fs_lib.write_file(driver, table.concat({
      "package.path = './?.lua;' .. package.path",
      "require('test.bootstrap').install_package_paths()",
      "os.exit(require('packages.clean.cli').main({}, { repo_root = arg[1] }))",
      "",
    }, "\n")))
    local command = "PATH=" .. shell_lib.shell_quote(_system_path()) .. " "
      .. shell_lib.shell_quote(require("foundation.lua54").lua54_bin()) .. " "
      .. shell_lib.shell_quote(driver) .. " " .. shell_lib.shell_quote(root)
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
    check.equal(0, clean_cli.main({}, { repo_root = root }))
    check.is_true(fs_lib.is_dir(root))
  end, debug.traceback)
  fs_lib.remove_path(root)
  if not ok then
    error(err)
  end
end)

it("unknown arguments are a usage error and touch nothing", function()
  _with_fixture(function(root)
    check.equal(2, clean_cli.main({ "--bogus" }, { repo_root = root }))
    check.is_true(fs_lib.path_exists(path_lib.join_path(root, "luacov.stats.out")))
    check.is_true(fs_lib.is_dir(path_lib.join_path(root, "build")))
  end)
end)

end)
