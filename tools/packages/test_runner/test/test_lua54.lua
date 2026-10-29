---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/test_runner/test/test_lua54.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local bin = require("packages.test_runner.lua54")

describe("lua54 runner entry", function()
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
