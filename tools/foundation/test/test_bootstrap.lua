---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_bootstrap.lua") end

require("test.bootstrap").install_package_paths()

local check = require("luassert")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local tool_lockfile = require("foundation.tool_lockfile")
local test_source = debug.getinfo(1, "S").source:gsub("^@", "")
local test_dir = test_source:match("^(.*)/[^/]+$") or "tools/foundation/test"
local runtime_paths = dofile(test_dir .. "/../runtime_paths.lua")
local bootstrap_path = test_dir .. "/../bootstrap.lua"
local bootstrap = require("foundation.bootstrap")
local process_lock = require("foundation.process_lock")
local native_lua = assert(arg[-1], "native Lua interpreter identity required")

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
    -- 单元用例聚焦安装结果与错误分类,直接执行锁回调;真实目录锁由上面的
    -- 跨进程假 luarocks 用例经公共 ensure_busted_tree 完整覆盖。
    { target = process_lock, key = "with_lock", value = function(_, fn) return fn() end },
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
-- lua.cmd 垫片,真解释器在第二行;安装前缀必须由后者导出。
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

-- #112:临时仓库根 + 锁文件,让 ensure_tool 走真实解析/拉取路径而不碰本仓 .toolcache。
-- cache_line 给出时预置一条新鲜的解析缓存(跳过 ls-remote,直达拉源码一步)。
local function _temp_tool_repo(cache_line)
  local root = env_lib.make_temp_path("bootstrap_unavailable_spec", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools")))
  check.is_true(fs_lib.write_file(path_lib.join_path(root, "tools/tools.lock"),
    "dry4lua https://example.invalid/eggy/dry4lua\n"))
  if cache_line ~= nil then
    check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, ".toolcache")))
    check.is_true(fs_lib.write_file(path_lib.join_path(root, ".toolcache/resolved-tools.tsv"), cache_line .. "\n"))
  end
  return { repo_root = root, tool_cache_dir = path_lib.join_path(root, ".toolcache") }
end

-- 断网替身:工具未装(luarocks list 失败),git 远端一律解析不到主机。
local function _offline_stubs()
  local real_exists = fs_lib.path_exists
  return {
    { target = fs_lib, key = "path_exists", value = function(path)
      if tostring(path):match("luarocks%.exe$") then return true end
      return real_exists(path)
    end },
    { target = proc_lib, key = "run_command", value = function(command)
      local probe = _native_probe(command)
      if probe then return probe end
      if command[1] == "git" then
        return { ok = false, output = "fatal: unable to access: Could not resolve host: example.invalid" }
      end
      return { ok = false, output = "" }
    end },
  }
end

describe("bootstrap", function()

it("parses the repo url lockfile format", function()
  local lock, err = tool_lockfile.parse_contents(table.concat({
    "# comment",
    "dry4lua http://example.invalid/eggy/dry4lua.git",
    "",
  }, "\n"))

  check.is_nil(err)
  check.is_not_nil(lock)
  check.equal("http://example.invalid/eggy/dry4lua.git", lock.tools.dry4lua.url)
  check.same({ "dry4lua" }, lock.ordered)
end)

it("rejects unknown tools", function()
  local lock, err = tool_lockfile.parse_contents(
    "unknown http://example.invalid/eggy/unknown\n"
  )

  check.is_nil(lock)
  check.truthy(tostring(err):find("unknown tool", 1, true) ~= nil)
end)

-- #94:旧 CRAP/变异/架构工具退场后,锁文件白名单不再接受它们。
it("rejects retired quality tools", function()
  for _, name in ipairs({ "arch_view", "crap4lua", "mutate4lua" }) do
    local lock, err = tool_lockfile.parse_contents(name .. " http://example.invalid/eggy/" .. name .. "\n")
    check.is_nil(lock)
    check.truthy(tostring(err):find("unknown tool", 1, true) ~= nil, name)
  end
end)

it("install appends luarocks tree paths", function()
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
  check.is_true(fs_lib.write_file(path_lib.join_path(root, "tools/tools.lock"), ""))

  local original = package.path
  package.path = "/sentinel/?.lua"
  local fresh_bootstrap = dofile(bootstrap_path)
  fresh_bootstrap.install(nil, { cwd = root })
  local path = package.path
  package.path = original
  fs_lib.remove_path(root)

  check.truthy(path:find("/.toolcache/luarocks/share/lua/5.4/?.lua", 1, true) ~= nil)
  check.truthy(path:find("/.toolcache/luarocks/share/lua/5.4/?/init.lua", 1, true) ~= nil)
end)

it("install appends luarocks tree cpath", function()
  local root = env_lib.make_temp_path("bootstrap_cpath_spec", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "src")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "test")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools/foundation")))
  check.is_true(fs_lib.copy_file(
    "tools/foundation/package_path_helper.lua",
    path_lib.join_path(root, "tools/foundation/package_path_helper.lua")
  ))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools")))
  check.is_true(fs_lib.write_file(path_lib.join_path(root, "tools/tools.lock"), ""))

  local original = package.cpath
  package.cpath = "/sentinel/?.so"
  local fresh_bootstrap = dofile(bootstrap_path)
  fresh_bootstrap.install(nil, { cwd = root })
  local cpath = package.cpath
  package.cpath = original
  fs_lib.remove_path(root)

  check.truthy(cpath:find("/.toolcache/luarocks/lib/lua/5.4/?.so", 1, true) ~= nil)
end)

it("resolves a repo root from the lockfile based tool layout", function()
  local root = path_lib.join_path(
    "tmp",
    "runtime_paths_spec_$__monopoly_runtime_paths_unset__ path"
  )
  fs_lib.remove_path(root)

  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "src")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "test")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools/foundation")))
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "tools")))
  check.is_true(fs_lib.write_file(path_lib.join_path(root, "tools/tools.lock"), ""))

  local env = runtime_paths.resolve({
    cwd = root,
    source_path = "tools/foundation/bootstrap.lua",
  })

  fs_lib.remove_path(root)

  check.equal(path_lib.normalize_path(root), env.repo_root)
  check.equal(path_lib.join_path(path_lib.normalize_path(root), ".toolcache"), env.tool_cache_dir)
end)

it("ensure busted tree skips install when marker exists", function()
  local ensure_calls = 0
  local command_calls = 0
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path)
      check.equal("/repo/.toolcache/luarocks/share/lua/5.4/busted/runner.lua", path)
      return true
    end },
    { target = fs_lib, key = "ensure_dir", value = function()
      ensure_calls = ensure_calls + 1
      return true
    end },
    { target = proc_lib, key = "run_command", value = function()
      command_calls = command_calls + 1
      return { ok = true }
    end },
  }, function()
    check.is_true(bootstrap.ensure_busted_tree("/repo"))
  end)
  -- lint-allow: call-count fs_lib.ensure_dir 是文件系统边界,零调用=marker 已在时不建目录
  check.equal(0, ensure_calls)
  -- lint-allow: call-count proc_lib.run_command 是子进程边界,零调用=marker 已在时不启动 luarocks 安装
  check.equal(0, command_calls)
end)

it("ensure busted tree installs pinned rock and checks marker", function()
  -- marker 是否已落地由安装命令决定:安装前 path_exists  false,安装后 true。
  -- 用可见的安装结果建模,而不是数 path_exists 被调了几次。
  local installed = false
  local captured_command
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path)
      if path:match("luarocks%.exe$") then return true end
      -- 解释器候选路径(/opt/homebrew/bin/lua5.4 之类)不是 marker。
      if path:match("%.lua$") == nil then return false end
      check.equal("/repo/.toolcache/luarocks/share/lua/5.4/busted/runner.lua", path)
      return installed
    end },
    { target = fs_lib, key = "ensure_dir", value = function(path)
      check.equal("/repo/.toolcache/luarocks", path)
      return true
    end },
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      local probe = _native_probe(command)
      if probe then return probe end
      captured_command = command
      installed = true
      return { ok = true, output = "" }
    end },
  }, function()
    check.is_true(bootstrap.ensure_busted_tree("/repo"))
  end)
  check.same({ "--tree", "/repo/.toolcache/luarocks", "--lua-version", "5.4" },
    { table.unpack(captured_command, 2, 5) })
  check.same({ "install", "busted", "2.3.0-1", "--deps-mode", "one" },
    { table.unpack(captured_command, 8) })
  check.equal("--lua-dir", captured_command[6])
  -- --lua-dir 取真实解释器(lua.exe)所在前缀,而不是 where.exe 首行的
  -- lua.cmd / lua.bat 垫片目录。
  check.equal(_LUAROCKS_PREFIX, captured_command[7])
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

local function _assert_concurrent_cold_bootstrap(kinds)
  local root = env_lib.make_temp_path("bootstrap lock 中文 space", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(path_lib.join_path(root, "fake-bin")))
  local worker = path_lib.join_path(root, "worker.lua")
  local fake_script = path_lib.join_path(root, "fake_luarocks.lua")
  local fake_exe = path_lib.join_path(root, "fake_luarocks.cmd")
  local fake_git_script = path_lib.join_path(root, "fake_git.lua")
  local fake_git_exe = path_lib.join_path(root, "fake-bin/git.cmd")
  local sha = string.rep("a", 40)
  local needs_dry = kinds[1] == "dry4lua" or kinds[2] == "dry4lua"

  if needs_dry then
    -- resolved cache 只创建 .toolcache,不预建其下的 luarocks tree。
    check.is_true(fs_lib.write_file(path_lib.join_path(root, "tools/tools.lock"),
      "dry4lua https://example.invalid/eggy/dry4lua.git\n"))
    check.is_true(fs_lib.write_file(path_lib.join_path(root, ".toolcache/resolved-tools.tsv"),
      "dry4lua\t" .. sha .. "\t-\t" .. tostring(os.time()) .. "\n"))
  end

  -- 两个 worker 都到齐后才进入公共 ensure 接口。假 git 与假 luarocks 不起网络;
  -- 假 install/remove/make 用独立目录锁模拟真实树锁,未串行化时必报竞争错误。
  check.is_true(fs_lib.write_file(worker, [[
local function exists(path)
  local file = io.open(path, "rb")
  if file then file:close() end
  return file ~= nil
end
local root, lane, kind = arg[1], arg[2], arg[3]
local ready = root .. "/ready-" .. lane
local file = assert(io.open(ready, "wb"))
file:write("ready")
file:close()
local deadline = os.time() + 10
while not exists(root .. "/ready-1") or not exists(root .. "/ready-2") do
  if os.time() >= deadline then io.stderr:write("worker barrier timeout\n"); os.exit(9) end
end
require("test.bootstrap").install_package_paths()
local bootstrap = require("foundation.bootstrap")
local ok, err, unavailable
if kind == "dry4lua" then
  ok, err, unavailable = bootstrap.ensure_tool(kind, {
    repo_root = root,
    tool_cache_dir = root .. "/.toolcache",
  })
else
  ok, err, unavailable = bootstrap.ensure_busted_tree(root)
end
if unavailable ~= nil then io.stderr:write(tostring(err) .. "\n"); os.exit(3) end
if not ok then io.stderr:write(tostring(err) .. "\n"); os.exit(1) end
io.write("BOOTSTRAP_OK " .. kind .. "\n")
]]))
  check.is_true(fs_lib.write_file(fake_git_script, [[
local sha = string.rep("a", 40)
if arg[1] == "clone" then
  local destination = arg[#arg]
  assert(os.execute('mkdir "' .. destination:gsub("/", "\\") .. '" 2>nul'))
  local file = assert(io.open(destination .. "/controlled-source.txt", "wb"))
  file:write("source")
  file:close()
elseif arg[1] == "-C" and arg[3] == "rev-parse" then
  io.write(sha .. "\n")
elseif arg[1] == "ls-remote" then
  io.write(sha .. "\tHEAD\n")
else
  io.stderr:write("unexpected fake git argv\n")
  os.exit(2)
end
]]))
  check.is_true(fs_lib.write_file(fake_script, [[
local tree, action
for index = 1, #arg do
  if arg[index] == "--tree" then tree = arg[index + 1] end
  if arg[index] == "install" or arg[index] == "remove"
      or arg[index] == "make" or arg[index] == "list" then
    action = arg[index]
  end
end
assert(tree and action, "fake luarocks requires a tree and action")
local state = tree .. "/.controlled-dry4lua-installed"
if action == "list" then
  local installed = io.open(state, "rb")
  if installed then
    local version = installed:read("*a")
    installed:close()
    io.write("dry4lua " .. version .. " installed\n")
  end
  return
end
local lock = tree .. "/.controlled-fake-tree-lock"
local native_lock = lock:gsub("/", "\\")
local created = os.execute('mkdir "' .. native_lock .. '" 2>nul')
if created ~= true then
  io.stderr:write("Error: another process requires exclusive write access to the tree\n")
  os.exit(1)
end
local deadline = os.time() + 2
while os.time() < deadline do end
if action == "remove" then
  os.remove(state)
elseif action == "install" then
  local marker = tree .. "/share/lua/5.4/busted/runner.lua"
  local parent = marker:match("^(.*)/[^/]+$"):gsub("/", "\\")
  assert(os.execute('mkdir "' .. parent .. '" 2>nul'))
  local file = assert(io.open(marker, "wb"))
  file:write("-- controlled fake busted\n")
  file:close()
elseif action == "make" then
  local file = assert(io.open(state, "wb"))
  file:write("1.0.0-1")
  file:close()
end
assert(os.execute('rmdir "' .. native_lock .. '" 2>nul'))
io.write("FAKE_" .. action:upper() .. "_OK\n")
]]))
  local shell_lib = require("foundation.shell")
  check.is_true(fs_lib.write_file(fake_exe, "@echo off\r\n"
    .. shell_lib.build_command({ native_lua, fake_script }) .. " %*\r\n"))
  check.is_true(fs_lib.write_file(fake_git_exe, "@echo off\r\n"
    .. shell_lib.build_command({ native_lua, fake_git_script }) .. " %*\r\n"))

  local run_ok, run_err = xpcall(function()
    local lanes = {}
    for lane = 1, 2 do
      lanes[lane] = {
        label = "cold-" .. kinds[lane],
        cmd = { native_lua, worker, root, tostring(lane), kinds[lane] },
      }
    end
    local ok, results = require("foundation.parallel_lanes").run(lanes, {
      stream = false,
      timeout = 45,
      env = {
        LUA54_BIN = native_lua,
        MONOPOLY_LUAROCKS_EXE = fake_exe,
        PATH = path_lib.join_path(root, "fake-bin") .. ";"
          .. assert(os.getenv("SystemRoot")) .. "\\System32",
      },
    })
    local diagnostics = {}
    for _, result in ipairs(results) do
      diagnostics[#diagnostics + 1] = result.label .. ": " .. tostring(result.output)
      check.is_true(result.ok, result.output)
      check.equal(0, result.exit_code)
      check.matches("BOOTSTRAP_OK", result.output, 1, true)
      check.is_nil(result.output:find("requires exclusive write access", 1, true))
    end
    check.is_true(ok, table.concat(diagnostics, "\n"))
    check.is_true(fs_lib.path_exists(path_lib.join_path(root,
      ".toolcache/luarocks/share/lua/5.4/busted/runner.lua")))
    if needs_dry then
      check.is_true(fs_lib.path_exists(path_lib.join_path(root,
        ".toolcache/luarocks/.controlled-dry4lua-installed")))
    end
  end, debug.traceback)
  fs_lib.remove_path(root)
  assert(run_ok, run_err)
end

it("serializes concurrent busted installs when the cache tree is absent", function()
  _assert_concurrent_cold_bootstrap({ "busted", "busted" })
end)

it("serializes dry4lua builds with busted installs on the shared tree", function()
  _assert_concurrent_cold_bootstrap({ "busted", "dry4lua" })
end)

it("ensure busted tree reports missing post install marker", function()
  -- 安装命令成功但 marker 仍不存在:可见行为是返回 nil + 明确错误。
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path)
      return path:match("luarocks%.exe$") ~= nil
    end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      return _native_probe(command) or { ok = true, output = "" }
    end },
  }, function()
    local ok, err = bootstrap.ensure_busted_tree("/repo")
    check.is_nil(ok)
    check.equal("busted not found in luarocks tree after install", err)
  end)
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

it("luarocks command reuses exported MONOPOLY_LUAROCKS_EXE without probing", function()
  -- 覆写路径故意避开 LOCALAPPDATA 默认回退位置,才能区分两条解析路径。
  local override = "D:/native/LuaRocks/bin/luarocks.exe"
  local real_getenv = os.getenv
  local captured_command
  _with_stubs({
    { target = os, key = "getenv", value = function(name)
      if name == "LUA54_BIN" then return nil end
      if name == "MONOPOLY_LUAROCKS_EXE" then return override end
      return real_getenv(name)
    end },
    { target = fs_lib, key = "path_exists", value = function(path)
      if path == override then return true end
      return false
    end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      local probe = _native_probe(command)
      if probe then return probe end
      captured_command = command
      return { ok = true, output = "" }
    end },
  }, function()
    bootstrap.ensure_luacheck_tree("/repo")
  end)
  check.equal(override, captured_command[1])
end)

it("missing MONOPOLY_LUAROCKS_EXE override falls back to probing", function()
  local override = "D:/native/LuaRocks/bin/luarocks.exe"
  local real_getenv = os.getenv
  local captured_command
  _with_stubs({
    { target = os, key = "getenv", value = function(name)
      if name == "LUA54_BIN" then return nil end
      if name == "MONOPOLY_LUAROCKS_EXE" then return override end
      return real_getenv(name)
    end },
    { target = fs_lib, key = "path_exists", value = function(path)
      if path == override then return false end
      return tostring(path):match("luarocks%.exe$") ~= nil
    end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      if command[1] == "where.exe" and command[2] == "luarocks.exe" then
        return { ok = false, output = "" }
      end
      local probe = _native_probe(command)
      if probe then return probe end
      captured_command = command
      return { ok = true, output = "" }
    end },
  }, function()
    bootstrap.ensure_luacheck_tree("/repo")
  end)
  -- 覆写失效时退回探测链(where 不命中 → LOCALAPPDATA 默认位置)。
  check.truthy(captured_command[1]:match("luarocks%.exe$") ~= nil)
  check.is_not.equal(override, captured_command[1])
end)

it("ensure busted tree propagates tree creation failure", function()
  local command_calls = 0
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path) return path:match("luarocks.exe$") ~= nil end },
    { target = fs_lib, key = "ensure_dir", value = function()
      return nil, "mkdir failed"
    end },
    { target = proc_lib, key = "run_command", value = function()
      command_calls = command_calls + 1
      return { ok = true }
    end },
  }, function()
    local ok, err = bootstrap.ensure_busted_tree("/repo")
    check.is_nil(ok)
    check.equal("mkdir failed", err)
  end)
  -- lint-allow: call-count proc_lib.run_command 是子进程边界,零调用=建树失败后不启动安装进程
  check.equal(0, command_calls)
end)

it("ensure luacov tree reports install failure", function()
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path) return path:match("luarocks.exe$") ~= nil end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      local probe = _native_probe(command)
      if probe then return probe end
      check.equal("luacov", command[#command - 3])
      check.equal("0.17.0-1", command[#command - 2])
      return { ok = false, output = "offline" }
    end },
  }, function()
    local ok, err = bootstrap.ensure_luacov_tree("/repo")
    check.is_nil(ok)
    check.equal("luarocks install failed for luacov: offline", err)
  end)
end)

it("ensure luacov tree reports missing post install marker", function()
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path) return path:match("luarocks.exe$") ~= nil end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      return _native_probe(command) or { ok = true, output = "" }
    end },
  }, function()
    local ok, err = bootstrap.ensure_luacov_tree("/repo")
    check.is_nil(ok)
    check.equal("luacov not found in luarocks tree after install", err)
  end)
end)

-- #93:crapper 的 Lua 覆盖率走 luacov.reporter.lcov;只能装进项目 tree,不能借全局 tree。
it("ensure luacov lcov reporter tree stops when luacov dependency fails", function()
  local command_calls = 0
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path)
      check.equal("/repo/.toolcache/luarocks/share/lua/5.4/luacov/reporter/lcov.lua", path)
      return false
    end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function()
      command_calls = command_calls + 1
      return { ok = true }
    end },
    { target = bootstrap, key = "ensure_luacov_tree", value = function(repo_root)
      check.equal("/repo", repo_root)
      return nil, "luacov failed"
    end },
  }, function()
    local ok, err = bootstrap.ensure_luacov_reporter_lcov_tree("/repo")
    check.is_nil(ok)
    check.equal("luacov failed", err)
  end)
  -- lint-allow: call-count proc_lib.run_command 是子进程边界,零调用=luacov 依赖失败后不启动 lcov 安装
  check.equal(0, command_calls)
end)

it("ensure luacov lcov reporter tree installs the pinned rock", function()
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path) return path:match("luarocks.exe$") ~= nil end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "command_exists", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      local probe = _native_probe(command)
      if probe then return probe end
      check.equal("luacov-reporter-lcov", command[#command - 3])
      check.equal("0.2-0", command[#command - 2])
      return { ok = false, output = "offline" }
    end },
    { target = bootstrap, key = "ensure_luacov_tree", value = function() return true end },
  }, function()
    local ok, err = bootstrap.ensure_luacov_reporter_lcov_tree("/repo")
    check.is_nil(ok)
    check.equal("luarocks install failed for luacov-reporter-lcov: offline", err)
  end)
end)

-- #112:自举的网络类失败是「不可用」,不是「失败」——第三返回值标出工具与步骤,
-- 调用方据此退 3,而不是把断网说成测试回归。
it("ensure tool reports unresolvable upstream head as unavailable", function()
  local env = _temp_tool_repo()
  local ok, err, unavailable
  _with_stubs(_offline_stubs(), function()
    ok, err, unavailable = bootstrap.ensure_tool("dry4lua", env)
  end)
  fs_lib.remove_path(env.repo_root)
  check.is_nil(ok)
  check.truthy(tostring(err):find("git ls-remote failed", 1, true), tostring(err))
  check.equal("unavailable", unavailable.status)
  check.equal("dry4lua", unavailable.tool)
  check.equal("resolve", unavailable.step)
  check.equal(3, unavailable.exit_code)
end)

it("ensure tool reports failed source clone as unavailable", function()
  local env = _temp_tool_repo("dry4lua\t" .. string.rep("a", 40) .. "\t-\t" .. tostring(os.time()))
  local ok, err, unavailable
  _with_stubs(_offline_stubs(), function()
    ok, err, unavailable = bootstrap.ensure_tool("dry4lua", env)
  end)
  fs_lib.remove_path(env.repo_root)
  check.is_nil(ok)
  check.truthy(tostring(err):find("git clone failed", 1, true), tostring(err))
  check.equal("dry4lua", unavailable.tool)
  check.equal("fetch", unavailable.step)
end)

-- 上游仓库不存在不是网络问题:按失败原因分类,照旧是真实失败。
it("ensure tool keeps a missing upstream repository as a real failure", function()
  local env = _temp_tool_repo()
  local stubs = _offline_stubs()
  local offline_run = stubs[2].value
  stubs[2].value = function(command)
    if command[1] == "git" then return { ok = false, output = "remote: Repository not found." } end
    return offline_run(command)
  end
  local ok, err, unavailable
  _with_stubs(stubs, function()
    ok, err, unavailable = bootstrap.ensure_tool("dry4lua", env)
  end)
  fs_lib.remove_path(env.repo_root)
  check.is_nil(ok)
  check.truthy(tostring(err):find("Repository not found", 1, true), tostring(err))
  check.is_nil(unavailable)
end)

-- 构建失败要看原因:下载依赖失败是不可用,编译/构建错误是锁定版本或源码坏了,真实失败。
local function _ensure_with_make_output(make_output)
  local env = _temp_tool_repo("dry4lua\t" .. string.rep("a", 40) .. "\t-\t" .. tostring(os.time()))
  local stubs = _offline_stubs()
  stubs[2].value = function(command)
    local probe = _native_probe(command)
    if probe then return probe end
    if command[1] == "git" and command[2] == "clone" then return { ok = true, output = "" } end
    if command[1] == "git" then return { ok = true, output = string.rep("b", 40) .. "\n" } end
    for _, token in ipairs(command) do
      if token == "make" then return { ok = false, output = make_output } end
    end
    return { ok = false, output = "" }
  end
  local ok, err, unavailable
  _with_stubs(stubs, function()
    ok, err, unavailable = bootstrap.ensure_tool("dry4lua", env)
  end)
  fs_lib.remove_path(env.repo_root)
  check.is_nil(ok)
  check.truthy(tostring(err):find("luarocks make failed for dry4lua", 1, true), tostring(err))
  return unavailable
end

it("ensure tool reports dependency download failure during build as unavailable", function()
  local unavailable = _ensure_with_make_output("Error: Failed downloading https://luarocks.org/manifest - timed out")
  check.equal("build", unavailable.step)
  check.equal("dry4lua", unavailable.tool)
end)

it("ensure tool keeps a build error as a real failure", function()
  check.is_nil(_ensure_with_make_output("Error: Build error: Failed compiling object src/lfs.o"))
end)

-- 宁红勿假:编译报错里出现 ssl/tls/proxy/timed out 字样不等于网络失败。
it("ensure tool keeps an openssl header compile error as a real failure", function()
  check.is_nil(_ensure_with_make_output(
    "src/tls_proxy.c:3:10: fatal error: openssl/ssl.h: No such file or directory\n"
      .. "Error: Build error: Failed compiling object src/tls_proxy.o"))
end)

it("ensure tool keeps a timed out build step as a real failure", function()
  check.is_nil(_ensure_with_make_output("Error: Build error: command timed out after 600s"))
end)

-- ssh 形态的「仓库不存在」也带 Could not read from remote repository,不是网络问题。
it("ensure tool keeps an ssh repository not found as a real failure", function()
  local env = _temp_tool_repo()
  local stubs = _offline_stubs()
  local offline_run = stubs[2].value
  stubs[2].value = function(command)
    if command[1] == "git" then
      return { ok = false, output = "ERROR: Repository not found.\nfatal: Could not read from remote repository." }
    end
    return offline_run(command)
  end
  local unavailable
  _with_stubs(stubs, function()
    unavailable = select(3, bootstrap.ensure_tool("dry4lua", env))
  end)
  fs_lib.remove_path(env.repo_root)
  check.is_nil(unavailable)
end)

it("ensure tool reports a git tls handshake failure as unavailable", function()
  local env = _temp_tool_repo()
  local stubs = _offline_stubs()
  local offline_run = stubs[2].value
  stubs[2].value = function(command)
    if command[1] == "git" then
      return { ok = false, output = "fatal: unable to access: schannel: failed to receive handshake, SSL/TLS connection failed" }
    end
    return offline_run(command)
  end
  local unavailable
  _with_stubs(stubs, function()
    unavailable = select(3, bootstrap.ensure_tool("dry4lua", env))
  end)
  fs_lib.remove_path(env.repo_root)
  check.equal("resolve", unavailable.step)
end)

-- 锁文件缺项是仓内缺陷,照旧是真实失败,不能被降级成「不可用」。
it("ensure tool keeps lockfile defects as real failures", function()
  local env = _temp_tool_repo()
  check.is_true(fs_lib.write_file(path_lib.join_path(env.repo_root, "tools/tools.lock"), "# no tools\n"))
  local ok, err, unavailable = bootstrap.ensure_tool("dry4lua", env)
  fs_lib.remove_path(env.repo_root)
  check.is_nil(ok)
  check.equal("tool missing from lockfile: dry4lua", err)
  check.is_nil(unavailable)
end)

it("ensure luacheck tree reports install failure as unavailable", function()
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path) return path:match("luarocks.exe$") ~= nil end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      return _native_probe(command) or { ok = false, output = "Error: Failed downloading luacheck" }
    end },
  }, function()
    local ok, err, unavailable = bootstrap.ensure_luacheck_tree("/repo")
    check.is_nil(ok)
    check.truthy(tostring(err):find("luarocks install failed for luacheck", 1, true), tostring(err))
    check.equal("luacheck", unavailable.tool)
    check.equal("install", unavailable.step)
  end)
end)

it("ensure luacheck tree keeps a compile failure as a real failure", function()
  _with_stubs({
    { target = fs_lib, key = "path_exists", value = function(path) return path:match("luarocks.exe$") ~= nil end },
    { target = fs_lib, key = "ensure_dir", value = function() return true end },
    { target = proc_lib, key = "run_command", value = function(command)
      return _native_probe(command) or { ok = false, output = "Error: Build error: Failed compiling object lfs.o" }
    end },
  }, function()
    local ok, err, unavailable = bootstrap.ensure_luacheck_tree("/repo")
    check.is_nil(ok)
    check.truthy(tostring(err):find("Failed compiling", 1, true), tostring(err))
    check.is_nil(unavailable)
  end)
end)

end)
