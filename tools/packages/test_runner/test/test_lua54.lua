---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/test_runner/test/test_lua54.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local bin = require("packages.test_runner.lua54")

describe("lua54 runner entry", function()
  -- 入口统一写 lua(ADR 0083):argv_prefix 的首项是「探测出来的那个 5.4 解释器」,
  -- 本机可能是 lua5.4 / lua54 / lua / lua.exe 任意一个(候选表按序取第一个通过的),
  -- 所以这里断言它是可执行的 5.4 解释器,不钉死具体名字。
  it("argv prefix defaults to a resolved Lua 5.4 interpreter and runner", function()
    local prefix = bin.argv_prefix()
    check.equal(2, #prefix)
    local interpreter = require("foundation.lua54")
    check.equal(interpreter.lua54_bin(), prefix[1])
    local proc = require("foundation.proc")
    local version = proc.run_command({ prefix[1], "-v" })
    check.truthy(version.ok, version.output)
    check.truthy(tostring(version.output):find("Lua 5%.4") ~= nil, version.output)
    check.truthy(tostring(prefix[2]):find("runner%.lua$"))
    check.truthy(tostring(prefix[2]):find("test_runner/runner", 1, true))
  end)
  it("runner path resolves the real busted entry", function()
    check.truthy(bin.runner_path():find("tools/packages/test_runner/runner%.lua$"))
  end)
end)
