---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/test_runner/test/test_lua54.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local bin = require("packages.test_runner.lua54")

describe("lua54 runner entry", function()
  -- 候选表只认 lua5.4(入口显式写 lua5.4,ADR 0073):LUA54_BIN 指向非 5.4 时
  -- detect_lua54 必须返回 nil,不能回落到 PATH 上碰巧叫 lua 的 5.1。
  it("selected interpreter rejects non Lua override", function()
    local proc = require("foundation.proc")
    local command = "LUA54_BIN=/bin/sh " .. require("foundation.shell").shell_quote(bin.lua54_bin())
      .. " -e " .. require("foundation.shell").shell_quote(
        "package.path=package.path..';./tools/?.lua'; "
        .. "assert(require('packages.test_runner.lua54').detect_lua54()==nil)")
    local result = proc.run_command(command)
    check.truthy(result.ok, result.output)
  end)

  it("argv prefix defaults to lua54 and runner", function()
    local prefix = bin.argv_prefix()
    check.equal(2, #prefix)
    check.truthy(tostring(prefix[1]):match("lua5%.4") ~= nil, tostring(prefix[1]))
    check.truthy(tostring(prefix[2]):find("runner%.lua$"))
    check.truthy(tostring(prefix[2]):find("test_runner/runner", 1, true))
  end)
  it("runner path resolves the real busted entry", function()
    check.truthy(bin.runner_path():find("tools/packages/test_runner/runner%.lua$"))
  end)
end)
