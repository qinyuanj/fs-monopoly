---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_bootstrap.lua") end

require("test.bootstrap").install_package_paths()

local check = require("luassert")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local test_source = debug.getinfo(1, "S").source:gsub("^@", "")
local test_dir = test_source:match("^(.*)/[^/]+$") or "tools/foundation/test"
local runtime_paths = dofile(test_dir .. "/../runtime_paths.lua")
local bootstrap_path = test_dir .. "/../bootstrap.lua"
local bootstrap = require("foundation.bootstrap")
local process_lock = require("foundation.process_lock")

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

-- 原生子进程替身:`where.exe <解释器>` 形如真实机器——首行是用户 shell 的
-- lua.cmd 垫片,真解释器在第二行。
local function _native_probe(command)
  if command[1] == "where.exe" then
    if command[2] == "luarocks.exe" then
      return { ok = false, output = "" }
    end
    return { ok = true, output = "C:\\tools\\shim\\lua.cmd\r\n"
      .. os.getenv("LOCALAPPDATA") .. "\\Programs\\Lua\\bin\\lua.exe\r\n" }
  end
  if command[2] == "-v" then return { ok = true, output = "Lua 5.4.6" } end
end

local _LUAROCKS_PREFIX = os.getenv("LOCALAPPDATA"):gsub("\\", "/") .. "/Programs/Lua"

describe("bootstrap", function()

-- 受控 Lua 环境退出项目后,bootstrap 只装仓库自身路径;不得再向 package.path /
-- package.cpath 注入任何仓内工具 tree。
it("install adds repository paths and leaves cpath alone", function()
  local root = env_lib.make_temp_path("bootstrap_spec", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "src")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "test")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools/foundation")))
  check.is_true(fs_lib.copy_file(
    "tools/foundation/package_path_helper.lua",
    path_lib.join_path(root, "tools/foundation/package_path_helper.lua")
  ))
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

  check.truthy(path:find(path_lib.normalize_path(root) .. "/tools/?.lua", 1, true),
    "root=" .. tostring(root) .. " path=" .. tostring(path))
  check.equal("/sentinel/?.so", cpath)
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

  local env = runtime_paths.resolve({
    cwd = root,
    source_path = "tools/foundation/bootstrap.lua",
  })

  fs_lib.remove_path(root)

  check.equal(path_lib.normalize_path(root), env.repo_root)
end)

it("process lock preserves parent creation errors", function()
  local real_ensure_parent = fs_lib.ensure_parent_dir
  local real_run_command = proc_lib.run_command
  local run_ok, run_err = xpcall(function()
    fs_lib.ensure_parent_dir = function() return nil, "controlled parent creation failure" end
    proc_lib.run_command = function()
      error("mkdir must not run when parent creation failed")
    end

    local acquired, err = process_lock.with_lock("Z:/controlled-parent-failure/.lock", function()
      error("lock callback must not run after parent creation failure")
    end)
    check.is_nil(acquired)
    check.equal("controlled parent creation failure", err)
  end, debug.traceback)
  fs_lib.ensure_parent_dir = real_ensure_parent
  proc_lib.run_command = real_run_command
  assert(run_ok, run_err)
end)

it("process lock preserves non contention mkdir errors instead of waiting", function()
  local real_run_command = proc_lib.run_command
  local real_path_exists = fs_lib.path_exists
  local real_ensure_parent = fs_lib.ensure_parent_dir
  local run_ok, run_err = xpcall(function()
    fs_lib.ensure_parent_dir = function() return true end
    proc_lib.run_command = function(command)
      if type(command) == "string" and command:find("mkdir ", 1, true) == 1 then
        return { ok = false, code = 5, output = "controlled mkdir access denied" }
      end
      error("non-contention mkdir failure must not enter the wait path")
    end
    fs_lib.path_exists = function() return false end

    local acquired, err = process_lock.with_lock("Z:/controlled-mkdir-failure/.lock", function()
      error("lock callback must not run after mkdir failure")
    end)
    check.is_nil(acquired)
    check.is_not_nil(err)
    check.matches("exit code 5", err, 1, true)
    check.matches("controlled mkdir access denied", err, 1, true)
  end, debug.traceback)
  proc_lib.run_command = real_run_command
  fs_lib.path_exists = real_path_exists
  fs_lib.ensure_parent_dir = real_ensure_parent
  assert(run_ok, run_err)
end)

it("tool discovery env exports resolved interpreter path and luarocks exe", function()
  _with_stubs({
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      return _native_probe(command) or { ok = false, output = "" }
    end },
    { target = fs_lib, key = "path_exists", value = function(path)
      return tostring(path):match("luarocks%.exe$") ~= nil
    end },
  }, function()
    local exported = bootstrap.tool_discovery_env()
    check.is_not_nil(exported)
    -- 裸候选解析到真实 .exe(where.exe 首行的 lua.cmd 垫片被跳过),子进程拿到
    -- 路径形态覆写后 path_exists 即过,不再逐个 where 探测。
    check.equal(_LUAROCKS_PREFIX .. "/bin/lua.exe", exported.LUA54_BIN)
    check.truthy(exported.MONOPOLY_LUAROCKS_EXE:match("luarocks%.exe$") ~= nil)
  end)
end)

end)
