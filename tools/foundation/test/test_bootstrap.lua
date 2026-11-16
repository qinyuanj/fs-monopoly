---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_bootstrap.lua") end

require("test.bootstrap").install_package_paths()

local check = require("luassert")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local lua54 = require("foundation.lua54")
local bootstrap = require("foundation.bootstrap")

-- 本文件自己的位置不靠 debug.getinfo:package.searchpath 问的是「require 会从哪装」,
-- 与 require 同源且 cwd 无关。
local bootstrap_path = assert(package.searchpath("foundation.bootstrap", package.path))
local foundation_dir = path_lib.parent_dir(bootstrap_path)
local repo_root = path_lib.parent_dir(path_lib.parent_dir(foundation_dir))
local runtime_path_ops = dofile(path_lib.join_path(foundation_dir, "runtime_path_ops.lua"))

local function _with_stubs(stubs, fn)
  local saved_lua54 = package.loaded["foundation.lua54"]
  package.loaded["foundation.lua54"] = nil
  -- #124:verify / spec-lane 现在把工具发现结果(LUA54_BIN / MONOPOLY_LUAROCKS_EXE)
  -- 导出进测试进程;本文件的替身语义基于「无导出」编写,统一先屏蔽,测试需要
  -- 覆写时在 stubs 列表里再放一个 os.getenv 替身即可(靠后的生效)。
  local real_getenv = os.getenv
  local effective = {
    { target = os, key = "getenv", value = function(name)
      if name == "LUA54_BIN" or name == "MONOPOLY_LUAROCKS_EXE" then return nil end
      return real_getenv(name)
    end },
  }
  for _, stub in ipairs(stubs) do
    effective[#effective + 1] = stub
  end
  local originals = {}
  for index, stub in ipairs(effective) do
    originals[index] = stub.target[stub.key]
    stub.target[stub.key] = stub.value
  end
  local ok, err = pcall(fn)
  for index = #effective, 1, -1 do
    local stub = effective[index]
    stub.target[stub.key] = originals[index]
  end
  package.loaded["foundation.lua54"] = saved_lua54
  if not ok then
    error(err, 0)
  end
end

-- 子进程替身:`command -v <解释器>` 形如真实 Linux 机器——一条绝对路径。
local function _native_probe(command)
  if type(command) == "string" and command:find("command -v", 1, true) then
    if command:find("luarocks", 1, true) then
      return { ok = true, output = "/usr/bin/luarocks\n" }
    end
    return { ok = true, output = "/usr/bin/lua5.4\n" }
  end
  if type(command) == "table" and command[2] == "-v" then return { ok = true, output = "Lua 5.4.6" } end
end

local _LUA54_PATH = "/usr/bin/lua5.4"

-- 子进程里跑一段 Lua(原生 Windows 上必须显式给解释器;cwd 由调用方定)。
local function _run_child(script, cwd)
  local path = path_lib.join_path(env_lib.make_temp_path("bootstrap_child", ""), "child.lua")
  check.truthy(fs_lib.write_file(path, script))
  local result = proc_lib.run_command({ lua54.lua54_bin(), path }, { cwd = cwd })
  fs_lib.remove_path(path_lib.parent_dir(path))
  return result
end

describe("bootstrap", function()

-- 受控 Lua 环境退出项目后,bootstrap 只装仓库自身路径;不得再向 package.path /
-- package.cpath 注入任何仓内工具 tree。
it("install adds repository paths and leaves cpath alone", function()
  local root = env_lib.make_temp_path("bootstrap_spec", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "src")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "test")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools/foundation")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools")))
  check.is_true(fs_lib.write_file(path_lib.join_path(root, "tools/cli.lua"), "return {}"))

  local original_path, original_cpath = package.path, package.cpath
  package.path = "/sentinel/?.lua"
  package.cpath = "/sentinel/?.so"
  local fresh_bootstrap = dofile(bootstrap_path)
  fresh_bootstrap.install(nil, { cwd = root, source_path = path_lib.join_path(root, "tools/cli.lua") })
  local path, cpath = package.path, package.cpath
  package.path, package.cpath = original_path, original_cpath
  fs_lib.remove_path(root)

  -- 7 条模式逐条钉住。旧实现要从仓根 dofile package_path_helper.lua 才拿到这张表,
  -- 所以临时仓根里必须存在那份文件;现在模式表住在 runtime_path_ops,仓根里
  -- 只需要目录形状本身。
  for _, relative in ipairs({
    "tools/?.lua", "tools/?/init.lua", "test/?.lua", "test/?/init.lua",
    "test/fixtures/?.lua", "?.lua", "?/init.lua",
  }) do
    local pattern = path_lib.normalize_path(root) .. "/" .. relative
    check.truthy(path:find(pattern, 1, true),
      "missing pattern " .. pattern .. " in " .. tostring(path))
  end
  check.equal("/sentinel/?.so", cpath)
end)

-- 模式表是纯数据:仓根 + 7 条相对模式,不依赖仓根里存在任何具体文件。
it("package patterns are pure data independent of the repo contents", function()
  local patterns = runtime_path_ops.package_patterns("D:/repo")
  check.same({
    "D:/repo/tools/?.lua",
    "D:/repo/tools/?/init.lua",
    "D:/repo/test/?.lua",
    "D:/repo/test/?/init.lua",
    "D:/repo/test/fixtures/?.lua",
    "D:/repo/?.lua",
    "D:/repo/?/init.lua",
  }, patterns)
end)

it("resolves a repo root from the standard tool layout", function()
  local root = path_lib.join_path(
    "tmp",
    "runtime_paths_spec_$__monopoly_runtime_paths_unset__ path"
  )
  fs_lib.remove_path(root)

  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "src")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "test")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools/foundation")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools")))
  check.is_true(fs_lib.write_file(path_lib.join_path(root, "tools/cli.lua"), "return {}"))

  local env = runtime_path_ops.resolve({
    cwd = root,
    source_path = "tools/foundation/bootstrap.lua",
  })

  fs_lib.remove_path(root)

  check.equal(path_lib.normalize_path(root), env.repo_root)
end)

-- 入口只需要一行引导:install_here 取**调用方 chunk** 的 source,不读 arg[0]。
-- `lua -e 'dofile(...)'` 下 arg[0] 是 lua.exe 自己,拿它当源路径必然解不出仓根。
it("install_here resolves the repo root from the calling chunk source", function()
  -- driver 放在仓内 tmp/(gitignored):它模拟的正是「入口 chunk 在仓内、进程入口
  -- 不是它」的场景 —— `lua -e 'dofile(<仓内入口>)'` 下 arg[0] 是 lua.exe 自己。
  local driver_dir = path_lib.join_path(repo_root, "tmp", env_lib.make_temp_path("bootstrap_here", ""):match("[^/\\]+$"))
  check.truthy(fs_lib.ensure_dir(driver_dir))
  local driver = path_lib.join_path(driver_dir, "driver.lua")
  check.truthy(fs_lib.write_file(driver, table.concat({
    "local bootstrap = dofile(" .. string.format("%q", bootstrap_path) .. ")",
    "local env = bootstrap.install_here()",
    "io.write(env.repo_root)",
    "",
  }, "\n")))

  -- cwd 也刻意放在仓外:仓根只能由调用方 chunk source 解出。
  local outside = path_lib.join_path(env_lib.make_temp_path("bootstrap_here_cwd", ""), "outside")
  check.truthy(fs_lib.ensure_dir(outside))
  local result = proc_lib.run_command({ lua54.lua54_bin(), "-e",
    "arg[0] = 'C:/Windows/Temp/lua.exe'; dofile(" .. string.format("%q", driver) .. ")" },
    { cwd = outside })
  fs_lib.remove_path(driver_dir)
  fs_lib.remove_path(path_lib.parent_dir(outside))

  check.is_true(result.ok == true, tostring(result.output))
  check.equal(path_lib.normalize_path(repo_root), path_lib.normalize_path(tostring(result.output):gsub("%s+$", "")))
end)

-- 装载期零 require:哨兵 package.path 下 dofile bootstrap.lua 必须成功且一个字都不加,
-- 加路径只发生在 install 里。进程内 `package.loaded` 早被灌满,钉不住这件事,所以走子进程。
it("loading bootstrap touches no module search path and requires nothing", function()
  local outside = path_lib.join_path(env_lib.make_temp_path("bootstrap_sentinel_cwd", ""), "outside")
  check.truthy(fs_lib.ensure_dir(outside))
  local result = _run_child(table.concat({
    "package.path = '/sentinel/?.lua'",
    "package.cpath = '/sentinel/?.so'",
    "local before = package.path",
    "local bootstrap = dofile(" .. string.format("%q", bootstrap_path) .. ")",
    "assert(package.path == before, 'bootstrap.lua must not touch package.path at load time')",
    "assert(package.cpath == '/sentinel/?.so', 'bootstrap.lua must not touch package.cpath')",
    "local env = bootstrap.install(" .. string.format("%q", path_lib.join_path(repo_root, "tools/cli.lua")) .. ")",
    "assert(require('foundation.primitives') ~= nil, 'installed paths must make foundation requireable')",
    "io.write(env.repo_root)",
    "",
  }, "\n"), outside)

  check.is_true(result.ok == true, tostring(result.output))
  check.equal(path_lib.normalize_path(repo_root), path_lib.normalize_path(tostring(result.output):gsub("%s+$", "")))
end)

-- bug 1:cli 入口原先只拼 root/tools/?,缺 repo_root/?.lua,只能靠默认的 ./?.lua 兜住,
-- 于是只有「cwd = 仓根」这一格能跑。
it("cli entry is cwd independent", function()
  local cli = path_lib.join_path(repo_root, "tools/cli.lua")
  local outside = path_lib.join_path(env_lib.make_temp_path("cli_cwd_matrix", ""), "outside")
  check.truthy(fs_lib.ensure_dir(outside))
  local cwds = {
    { label = "repo root", cwd = repo_root },
    { label = "tools/", cwd = path_lib.join_path(repo_root, "tools") },
    { label = "temp", cwd = outside },
  }
  local failures = {}
  for _, item in ipairs(cwds) do
    local result = proc_lib.run_command({ lua54.lua54_bin(), cli, "--help" }, { cwd = item.cwd })
    if result.ok ~= true then
      failures[#failures + 1] = item.label .. " -> " .. tostring(result.output)
    end
  end
  fs_lib.remove_path(path_lib.parent_dir(outside))
  check.equal("", table.concat(failures, "\n"))
end)

it("tool discovery env exports resolved interpreter path and luarocks exe", function()
  _with_stubs({
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      return _native_probe(command) or { ok = false, output = "" }
    end },
    { target = fs_lib, key = "path_exists", value = function(path)
      return tostring(path) == "/usr/bin/luarocks"
    end },
  }, function()
    local exported = bootstrap.tool_discovery_env()
    check.is_not_nil(exported)
    -- 裸候选解析到绝对路径,子进程拿到路径形态覆写后 path_exists 即过,
    -- 不再逐个 command -v 探测。
    check.equal(_LUA54_PATH, exported.LUA54_BIN)
    check.equal("/usr/bin/luarocks", exported.MONOPOLY_LUAROCKS_EXE)
  end)
end)

-- #236 风险①:导出的工具路径会交给**原生 Windows** 子进程(并非每次都经 bash),
-- MSYS 形态 /c/Users/... 会让 CreateProcess 报「The system cannot find the path
-- specified」。统一换成原生 C:/... 形态;这里用 MSYS 形态的 command -v 输出钉住。
it("tool discovery env exports native drive paths instead of MSYS /c form", function()
  _with_stubs({
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      if type(command) == "string" and command:find("command -v", 1, true) then
        if command:find("luarocks", 1, true) then
          return { ok = true, output = "/c/Users/x/AppData/Local/Programs/LuaRocks/bin/luarocks.exe\n" }
        end
        return { ok = true, output = "/c/Users/x/AppData/Local/Programs/Lua/bin/lua.exe\n" }
      end
      if type(command) == "table" and command[2] == "-v" then
        return { ok = true, output = "Lua 5.4.6" }
      end
    end },
    { target = fs_lib, key = "path_exists", value = function() return false end },
  }, function()
    local exported = bootstrap.tool_discovery_env()
    check.is_not_nil(exported)
    check.equal("C:/Users/x/AppData/Local/Programs/Lua/bin/lua.exe", exported.LUA54_BIN)
    check.equal("C:/Users/x/AppData/Local/Programs/LuaRocks/bin/luarocks.exe",
      exported.MONOPOLY_LUAROCKS_EXE)
    check.is_nil(tostring(exported.LUA54_BIN):find("^/c/"))
  end)
end)
end)
