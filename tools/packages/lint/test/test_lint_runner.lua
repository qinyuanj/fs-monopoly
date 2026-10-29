---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/lint/test/test_lint_runner.lua") end
require("test.bootstrap").install_package_paths()

local check = require("luassert")
local runner = require("packages.lint.runner")

local ROOT = "/home/user/.luarocks"

describe("lint runner controlled lua environment", function()

-- 预检失败:luacheck 不得被拉起,诊断原样透出(含安装命令),退 1 而非 3。
it("preflight failure is a real failure and never launches luacheck", function()
  local message = "受控 Lua 环境不满足本仓口径\n  luarocks --lua-version 5.4 install luacheck 1.2.0-1"
  local result = runner.execute({
    targets = { "tools/packages/lint" },
    preflight = function() return nil, message end,
    run_command = function() error("luacheck must not run when preflight failed") end,
  })
  check.equal(1, result.code)
  check.equal("", result.stdout)
  check.equal(message .. "\n", result.stderr)
end)

-- 预检通过:luacheck 经受控 Lua 环境装载器拉起,不再引用仓内工具 tree。
it("preflight success loads luacheck through the controlled environment", function()
  local seen
  local result = runner.execute({
    targets = { "tools/packages/lint" },
    preflight = function() return true, nil, { roots = { ROOT } } end,
    run_command = function(command)
      seen = command
      return { ok = true, output = "Total: 0 warnings\n" }
    end,
  })
  check.equal(0, result.code)
  local joined = table.concat(seen, " ")
  check.matches("lua_env.lua", joined, 1, true)
  check.matches("require_controlled('luacheck.main'", joined, 1, true)
  check.matches("'/home/user/.luarocks'", joined, 1, true)
  check.is_nil(joined:find("bootstrap", 1, true), joined)
end)

end)
