---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_lua54.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local interpreter = require("foundation.lua54")
local proc = require("foundation.proc")
local shell = require("foundation.shell")

-- 解释器发现(ADR 0083 第 7 条):入口统一写 `lua`,候选 lua5.4 → lua54 → lua →
-- lua.exe,每个都以 `-v` 校验含「Lua 5.4」;LUA54_BIN 可覆写。
-- 这几条只断言外部行为:选出来的解释器真能跑 5.4、覆写说了算、覆写失败不回落。
describe("lua54 interpreter selection", function()

  -- 候选顺序是契约的一部分:原生 Windows 上只有 lua/lua.exe,顺序错就等于选不到。
  it("candidate order follows the ADR contract", function()
    check.same({ "lua5.4", "lua54", "lua", "lua.exe" }, interpreter.candidates())
  end)

  -- 不带 LUA54_BIN 也要选出一个真能跑 5.4 的解释器——这是「只装 lua.exe 的机器上
  -- lua tools/cli.lua <子命令> 能跑」的单元级落点。
  it("detects a Lua 5.4 interpreter without LUA54_BIN", function()
    local selected = interpreter.detect_lua54()
    check.is_not_nil(selected, "no Lua 5.4 interpreter detected")
    local version = proc.run_command({ selected, "-v" })
    check.truthy(version.ok, version.output)
    check.truthy(tostring(version.output):find("Lua 5%.4") ~= nil, version.output)
  end)

  -- 覆写指到真 5.4 时以覆写为准(候选表不参与)。
  it("honors LUA54_BIN when it points at Lua 5.4", function()
    local native = interpreter.lua54_bin()
    local command = "LUA54_BIN=" .. shell.shell_quote(native) .. " " .. shell.shell_quote(native)
      .. " -e " .. shell.shell_quote(
        "package.path=package.path..';./tools/?.lua'; "
        .. "io.write(tostring(require('foundation.lua54').detect_lua54()))")
    local result = proc.run_command(command)
    check.truthy(result.ok, result.output)
    check.same(native, result.output)
  end)

  -- 覆写指到非 5.4 时返回 nil,不回落到候选表:显式覆写失败是环境问题,
  -- 静默换一个解释器会让「我明明指定了」变成不可解释的假绿。
  it("rejects a non Lua 5.4 override without falling back", function()
    local native = interpreter.lua54_bin()
    local command = "LUA54_BIN=" .. shell.shell_quote("C:/no such place/lua54.exe") .. " "
      .. shell.shell_quote(native) .. " -e " .. shell.shell_quote(
        "package.path=package.path..';./tools/?.lua'; "
        .. "assert(require('foundation.lua54').detect_lua54()==nil)")
    local result = proc.run_command(command)
    check.truthy(result.ok, result.output)
  end)
end)
