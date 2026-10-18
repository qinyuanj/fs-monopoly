---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_lua_env.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local lua_env = require("foundation.lua_env")

local ROOT = "C:\\Users\\dev\\AppData\\Roaming\\luarocks"
local ROCKS_DIR = ROOT .. "\\lib\\luarocks\\rocks-5.4"
local TREES = "{\n   {\n      name = \"user\",\n      root = \"" .. ROOT:gsub("\\", "\\\\") .. "\"\n   }\n}\n"

local GOOD = {
  busted = "2.3.0-1",
  luassert = "1.9.0-1",
  luacov = "0.17.0-1",
  ["luacov-reporter-lcov"] = "0.2-0",
  luacheck = "1.2.0-1",
}

-- 假 luarocks:config 返回固定 tree;list <name> 返回 installed 里该包的 porcelain 行
-- (故意做成与真实 luarocks 一致的子串匹配,验证实现按名称精确过滤)。
local function _fake_run(installed, calls)
  return function(command)
    calls[#calls + 1] = command
    local joined = table.concat(command, " ")
    if joined:find(" config rocks_trees", 1, true) then
      return { ok = true, output = TREES }
    end
    local name = joined:match(" list (%S+) %-%-porcelain")
    local lines = {}
    for pkg, version in pairs(installed) do
      if pkg:find(name, 1, true) then
        lines[#lines + 1] = pkg .. "\t" .. version .. "\tinstalled\t" .. ROCKS_DIR
      end
    end
    return { ok = true, output = table.concat(lines, "\n") .. "\n" }
  end
end

local function _preflight(installed)
  local calls = {}
  local ok, err, info = lua_env.preflight({
    luarocks_exe = "luarocks.exe",
    run_command = _fake_run(installed, calls),
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
