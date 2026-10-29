---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_lua54.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local interpreter = require("foundation.lua54")

describe("lua54 interpreter selection", function()
  -- 候选表只认 lua5.4(入口显式写 lua5.4,ADR 0073):LUA54_BIN 指向非 5.4 时
  -- detect_lua54 必须返回 nil,不能回落到 PATH 上碰巧叫 lua 的 5.1。
  it("selected interpreter rejects non Lua override", function()
    local proc = require("foundation.proc")
    local shell = require("foundation.shell")
    local command = "LUA54_BIN=/bin/sh " .. shell.shell_quote(interpreter.lua54_bin())
      .. " -e " .. shell.shell_quote(
        "package.path=package.path..';./tools/?.lua'; "
        .. "assert(require('foundation.lua54').detect_lua54()==nil)")
    local result = proc.run_command(command)
    check.truthy(result.ok, result.output)
  end)
end)
