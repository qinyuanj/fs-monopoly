---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_lua_env.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local lua_env = require("foundation.lua_env")
local lua54 = require("foundation.lua54")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local proc_lib = require("foundation.proc")

local ROOT = "C:\\Users\\dev\\AppData\\Roaming\\luarocks"
local EARLIER = "D:\\controlled\\earlier"
local LATER = "D:\\controlled\\later"
local TREES = "{\n   {\n      name = \"user\",\n      root = \"" .. ROOT:gsub("\\", "\\\\") .. "\"\n   }\n}\n"

local GOOD = {
  busted = "2.3.0-1",
  luassert = "1.9.0-1",
  luacov = "0.17.0-1",
  ["luacov-reporter-lcov"] = "0.2-0",
  luacheck = "1.2.0-1",
}

local function _trees(roots)
  local entries = {}
  for _, root in ipairs(roots) do
    entries[#entries + 1] = '   {\n      name = "tree",\n      root = "' .. root:gsub("\\", "\\\\") .. '"\n   }'
  end
  return "{\n" .. table.concat(entries, ",\n") .. "\n}\n"
end

-- 假 luarocks:config 返回给定 tree;list 按 --tree 返回该 tree 下的副本。
-- copies = { { name=, version=, root= } ... };名称仍是子串匹配(与真实 luarocks
-- 一致),验证实现按名称精确过滤。
local function _fake_run(copies, calls, roots)
  return function(command)
    calls[#calls + 1] = command
    local joined = table.concat(command, " ")
    if joined:find(" config rocks_trees", 1, true) then
      return { ok = true, output = _trees(roots or { ROOT }) }
    end
    local tree
    for _, argument in ipairs(command) do
      local value = argument:match("^%-%-tree=(.*)$")
      if value ~= nil then tree = value end
    end
    local name = command[#command - 1]
    local lines = {}
    for _, copy in ipairs(copies) do
      if name ~= nil and copy.name:find(name, 1, true) ~= nil
        and (tree == nil or copy.root == tree) then
        lines[#lines + 1] = copy.name .. "\t" .. copy.version .. "\tinstalled\t"
          .. copy.root .. "\\lib\\luarocks\\rocks-5.4"
      end
    end
    return { ok = true, output = table.concat(lines, "\n") .. "\n" }
  end
end

local function _copies(installed, root)
  local copies = {}
  for name, version in pairs(installed or {}) do
    if version ~= nil then
      copies[#copies + 1] = { name = name, version = version, root = root or ROOT }
    end
  end
  return copies
end

local function _preflight(installed, options)
  options = options or {}
  local calls = {}
  local ok, err, info = lua_env.preflight({
    luarocks_exe = "luarocks.exe",
    run_command = _fake_run(options.copies or _copies(installed), calls, options.roots),
    exists = options.exists or function() return true end,
  })
  return ok, err, info, calls
end

local function _with(name, version)
  local copy = {}
  for k, v in pairs(GOOD) do copy[k] = v end
  copy[name] = version
  return copy
end

describe("controlled lua environment preflight", function()
  it("passes when every package is inside the declared ranges", function()
    local ok, err, info = _preflight(GOOD)
    check.is_true(ok, err)
    check.equal(ROOT, info.roots[1])
  end)

  it("never installs or writes: only config and list are invoked", function()
    local _, _, _, calls = _preflight(GOOD)
    for _, command in ipairs(calls) do
      local joined = table.concat(command, " ")
      check.is_nil(joined:find(" install", 1, true), joined)
      check.is_nil(joined:find(" remove", 1, true), joined)
      check.is_nil(joined:find(" make", 1, true), joined)
    end
  end)

  it("fails on a missing package and prints an executable install command", function()
    local installed = _with("luacheck", nil)
    local ok, err = _preflight(installed)
    check.is_nil(ok)
    check.matches("luacheck", err, 1, true)
    check.matches("未安装", err, 1, true)
    check.matches("luarocks --lua-version 5.4 install luacheck 1.2.0-1", err, 1, true)
  end)

  it("fails when a version is below the lower bound", function()
    local ok, err = _preflight(_with("busted", "2.2.0-1"))
    check.is_nil(ok)
    check.matches("busted 2.2.0-1", err, 1, true)
    check.matches(">=2.3.0,<3", err, 1, true)
    check.matches("luarocks --lua-version 5.4 install busted 2.3.0-1", err, 1, true)
  end)

  it("fails when a version crosses the next major", function()
    local ok, err = _preflight(_with("luassert", "2.0.0-1"))
    check.is_nil(ok)
    check.matches("luassert 2.0.0-1", err, 1, true)
    check.matches("<2", err, 1, true)
  end)

  it("compares a zero major like luacov-reporter-lcov 0.2 against 0.2 and below 1", function()
    check.is_true((_preflight(_with("luacov-reporter-lcov", "0.2-0"))))
    check.is_nil((_preflight(_with("luacov-reporter-lcov", "0.1-1"))))
    check.is_nil((_preflight(_with("luacov-reporter-lcov", "1.0-0"))))
  end)

  it("does not let luacov satisfy luacov-reporter-lcov by substring", function()
    local installed = _with("luacov-reporter-lcov", nil)
    local ok, err = _preflight(installed)
    check.is_nil(ok)
    check.matches("luacov-reporter-lcov", err, 1, true)
  end)

  it("reports every violation at once", function()
    local installed = _with("busted", "2.2.0-1")
    installed.luacheck = nil
    local _, err = _preflight(installed)
    check.matches("busted", err, 1, true)
    check.matches("luacheck", err, 1, true)
  end)

  -- P1-a(#146):modules load in rocks_trees order, so an out-of-range copy in an
  -- earlier tree can win even when a later tree has a compliant one. Preflight
  -- must reject every installed copy outside its range, not accept any match.
  it("fails when an earlier tree holds an out-of-range copy and a later tree is compliant", function()
    local copies = _copies(GOOD, LATER)
    copies[#copies + 1] = { name = "busted", version = "2.2.0-1", root = EARLIER }
    local ok, err = _preflight(nil, { copies = copies, roots = { EARLIER, LATER } })
    check.is_nil(ok)
    check.matches("busted", err, 1, true)
    check.matches("2.2.0-1", err, 1, true)
    check.matches("2.3.0-1", err, 1, true)
  end)

  it("passes when every installed copy across trees is inside its range", function()
    local copies = _copies(GOOD, EARLIER)
    copies[#copies + 1] = { name = "busted", version = "2.3.0-1", root = LATER }
    local ok, err, info = _preflight(nil, { copies = copies, roots = { EARLIER, LATER } })
    check.is_true(ok, err)
    check.equal(2, #info.roots)
    check.equal("2.3.0-1", info.versions.busted)
    check.matches("busted/runner.lua", info.modules.busted, 1, true)
  end)

  -- 版本通过只说明 rock 清单口径对;模块还得真能从受控 tree 解析。
  it("fails when a package's module cannot be resolved from the controlled trees", function()
    local ok, err = _preflight(GOOD, { exists = function() return false end })
    check.is_nil(ok)
    check.matches("busted.runner", err, 1, true)
    check.matches("受控 Lua 环境", err, 1, true)
  end)

  it("fails when luarocks config yields no tree", function()
    local ok, err = lua_env.preflight({
      luarocks_exe = "luarocks.exe",
      run_command = function() return { ok = true, output = "{}\n" } end,
    })
    check.is_nil(ok)
    check.matches("rocks_trees", err, 1, true)
  end)

  it("fails when luarocks config itself fails", function()
    local ok, err = lua_env.preflight({
      luarocks_exe = "luarocks.exe",
      run_command = function() return { ok = false, output = "boom" } end,
    })
    check.is_nil(ok)
    check.matches("boom", err, 1, true)
  end)
end)

describe("controlled lua environment roots", function()
  it("resolves the tree roots without listing packages", function()
    local calls = {}
    local roots, err = lua_env.roots({
      luarocks_exe = "luarocks.exe",
      run_command = function(command)
        calls[#calls + 1] = command
        return { ok = true, output = TREES }
      end,
    })
    check.is_nil(err)
    check.equal(ROOT, roots[1])
    check.equal(1, #calls)
    check.equal("config", calls[1][4])
  end)

  it("fails when luarocks config fails", function()
    local roots, err = lua_env.roots({
      luarocks_exe = "luarocks.exe",
      run_command = function() return { ok = false, output = "boom" } end,
    })
    check.is_nil(roots)
    check.matches("boom", err, 1, true)
  end)

  it("fails when luarocks config yields no tree", function()
    local roots, err = lua_env.roots({
      luarocks_exe = "luarocks.exe",
      run_command = function() return { ok = true, output = "{}" } end,
    })
    check.is_nil(roots)
    check.matches("rocks_trees", err, 1, true)
  end)
end)

describe("controlled lua environment module origin", function()
  local roots = { ROOT }

  it("accepts a module resolved under the tree", function()
    local search = ROOT .. "/share/lua/5.4/?.lua"
    local file = lua_env.locate("luacheck.main", roots, search, function() return true end)
    check.equal(ROOT:gsub("\\", "/") .. "/share/lua/5.4/luacheck/main.lua", file)
  end)

  it("rejects a module that resolves outside the tree", function()
    local search = "C:/elsewhere/?.lua;" .. ROOT .. "/share/lua/5.4/?.lua"
    local file, err = lua_env.locate("luacheck.main", roots, search, function(path)
      return path:find("elsewhere", 1, true) ~= nil
    end)
    check.is_nil(file)
    check.matches("受控 Lua 环境以外", err, 1, true)
    check.matches("C:/elsewhere/luacheck/main.lua", err, 1, true)
  end)

  it("rejects a module that cannot be found at all", function()
    local file, err = lua_env.locate("luacheck.main", roots, ROOT .. "/?.lua", function() return false end)
    check.is_nil(file)
    check.matches("luacheck.main", err, 1, true)
  end)

  it("does not accept a sibling directory sharing the tree prefix", function()
    check.is_false(lua_env.is_inside(ROOT .. "-evil/share/lua/5.4/x.lua", roots))
    check.is_true(lua_env.is_inside(ROOT .. "/share/lua/5.4/x.lua", roots))
  end)
end)

-- P1-b(#150):require_controlled 必须约束整条装载链,而不只是入口模块。
-- 在干净子进程里验证,避免受限装载面污染测试进程。
local function _temp_dir(prefix)
  local root = env_lib.make_temp_path(prefix, ""):gsub("\\", "/")
  fs_lib.remove_path(root)
  assert(fs_lib.ensure_dir(root), "cannot create temp dir: " .. root)
  return root
end

local function _with_dirs(prefixes, fn)
  local dirs = {}
  for _, prefix in ipairs(prefixes) do dirs[prefix] = _temp_dir(prefix) end
  local ok, err = xpcall(function() fn(dirs) end, debug.traceback)
  for _, dir in pairs(dirs) do fs_lib.remove_path(dir) end
  if not ok then error(err) end
end

local function _write(root, relative, content)
  local path = root .. "/" .. relative
  local parent = path:match("^(.*)/[^/]+$")
  if parent ~= nil then assert(fs_lib.ensure_dir(parent)) end
  assert(fs_lib.write_file(path, content), "cannot write " .. path)
end

local function _roots_literal(roots)
  local parts = {}
  for _, root in ipairs(roots) do parts[#parts + 1] = string.format("%q", root) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function _run_controlled(module, roots, prelude, env_vars)
  local script = table.concat({
    prelude or "",
    "local lua_env = assert(loadfile('tools/foundation/lua_env.lua'))()",
    "local ok, result = pcall(lua_env.require_controlled, " .. string.format("%q", module)
      .. ", " .. _roots_literal(roots) .. ")",
    "if ok then print('OK') else print('ERR ' .. tostring(result)) end",
  }, "\n")
  local path = env_lib.make_temp_path("lua_env_child", ".lua")
  assert(fs_lib.write_file(path, script), "cannot write child script")
  local variables = {
    LUA_INIT = "",
    LUA_INIT_5_4 = "",
    LUA_PATH = "",
    LUA_PATH_5_4 = "",
    LUA_CPATH = "",
    LUA_CPATH_5_4 = "",
  }
  for key, value in pairs(env_vars or {}) do variables[key] = value end
  -- Lua 5.4 优先读带版本后缀的变量;两者都钉,测试才能确定子进程的装载面。
  variables.LUA_PATH_5_4 = variables.LUA_PATH
  variables.LUA_CPATH_5_4 = variables.LUA_CPATH
  local result = proc_lib.run_command({ lua54.lua54_bin(), path }, {
    env = variables,
    cwd = env_lib.current_dir(),
  })
  fs_lib.remove_path(path)
  return result
end

describe("controlled lua environment loading", function()

  it("loads a module whose whole dependency chain lives in the controlled tree", function()
    _with_dirs({ "controlled" }, function(dirs)
      _write(dirs.controlled, "share/lua/5.4/dep.lua", "return { value = 42 }")
      _write(dirs.controlled, "share/lua/5.4/entry.lua",
        "local dep = require('dep'); return { value = dep.value }")
      local result = _run_controlled("entry", { dirs.controlled })
      check.truthy(result.output:find("OK", 1, true) ~= nil, result.output)
    end)
  end)

  -- 外部 LUA_PATH 上有同名模块时,不得因为「能 require」就放行。
  it("does not resolve a module from an inherited LUA_PATH", function()
    _with_dirs({ "controlled", "external" }, function(dirs)
      _write(dirs.external, "fake.lua", "return { outside = true }")
      local result = _run_controlled("fake", { dirs.controlled }, nil, {
        LUA_PATH = dirs.external .. "/?.lua",
        LUA_CPATH = dirs.external .. "/?.dll",
      })
      check.truthy(result.output:find("ERR", 1, true) ~= nil, result.output)
      check.truthy(result.output:find("受控 Lua 环境", 1, true) ~= nil, result.output)
    end)
  end)

  -- C 模块同口径:外部 LUA_CPATH 上的候选不得被尝试装载。
  it("does not resolve a C module from an inherited LUA_CPATH", function()
    _with_dirs({ "controlled", "external" }, function(dirs)
      _write(dirs.external, "cfake.dll", "not a library")
      local result = _run_controlled("cfake", { dirs.controlled }, nil, {
        LUA_PATH = dirs.controlled .. "/?.lua",
        LUA_CPATH = dirs.external .. "/?.dll",
      })
      check.truthy(result.output:find("ERR", 1, true) ~= nil, result.output)
      check.truthy(result.output:find("受控 Lua 环境", 1, true) ~= nil, result.output)
    end)
  end)

  -- 传递依赖也必须留在受控 tree 内。
  it("does not resolve a transitive dependency from an inherited LUA_PATH", function()
    _with_dirs({ "controlled", "external" }, function(dirs)
      _write(dirs.controlled, "share/lua/5.4/entry.lua", "return require('dep')")
      _write(dirs.external, "dep.lua", "return { outside = true }")
      local result = _run_controlled("entry", { dirs.controlled }, nil, {
        LUA_PATH = dirs.external .. "/?.lua",
        LUA_CPATH = dirs.external .. "/?.dll",
      })
      check.truthy(result.output:find("ERR", 1, true) ~= nil, result.output)
      check.truthy(result.output:find("dep", 1, true) ~= nil, result.output)
      check.truthy(result.output:find("受控 Lua 环境", 1, true) ~= nil, result.output)
    end)
  end)

  -- 预加载模块绕过 searcher:若来源在受控 tree 之外,必须拒绝。
  it("denies a preloaded module whose source resolves outside the controlled trees", function()
    _with_dirs({ "controlled", "external" }, function(dirs)
      _write(dirs.external, "fake.lua", "return { outside = true }")
      local result = _run_controlled("fake", { dirs.controlled },
        "package.loaded.fake = { preloaded = true }", {
          LUA_PATH = dirs.external .. "/?.lua",
          LUA_CPATH = dirs.external .. "/?.dll",
        })
      check.truthy(result.output:find("ERR", 1, true) ~= nil, result.output)
      check.truthy(result.output:find("预加载", 1, true) ~= nil, result.output)
      check.truthy(result.output:find("受控 Lua 环境以外", 1, true) ~= nil, result.output)
    end)
  end)

  it("denies a preloaded module with no verifiable source", function()
    _with_dirs({ "controlled" }, function(dirs)
      local result = _run_controlled("fake", { dirs.controlled },
        "package.loaded.fake = { preloaded = true }", { LUA_PATH = "", LUA_CPATH = "" })
      check.truthy(result.output:find("ERR", 1, true) ~= nil, result.output)
      check.truthy(result.output:find("无法核对来源", 1, true) ~= nil, result.output)
    end)
  end)

  -- package.preload 的 loader 函数同样绕过文件来源校验。
  it("denies a module supplied by package.preload", function()
    _with_dirs({ "controlled" }, function(dirs)
      local result = _run_controlled("fake", { dirs.controlled },
        "package.preload.fake = function() return { preloaded = true } end",
        { LUA_PATH = "", LUA_CPATH = "" })
      check.truthy(result.output:find("ERR", 1, true) ~= nil, result.output)
      check.truthy(result.output:find("package.preload", 1, true) ~= nil, result.output)
    end)
  end)

end)
