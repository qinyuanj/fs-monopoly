---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_tool_availability.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local availability = require("foundation.tool_availability")

-- #131 实测断网输出(luarocks 3.12,HTTP(S)_PROXY 指向不可达地址)。
local _OFFLINE_INSTALL = "luarocks install failed for busted: Warning: Failed searching manifest: "
  .. "Failed downloading https://luarocks.org/manifest-5.4 - failed downloading https://luarocks.org/manifest-5.4\n"
  .. "Error: No results matching query were found for Lua 5.4."

local _CHILD_UNAVAILABLE = "[test_runner] status=unavailable tool=busted step=install\n"
  .. "[test_runner] 详情: " .. _OFFLINE_INSTALL .. "\n"

describe("tool availability", function()
  -- 入口进程(spec-lane / behavior_parallel)据子进程退出码与状态词认领不可用。
  it("relays a child that exited unavailable with its diagnostic", function()
    check.equal(_CHILD_UNAVAILABLE, availability.child_diagnostic(3, _CHILD_UNAVAILABLE))
  end)

  -- 宁红勿假:退 3 却没有状态词、或有状态词却不是退 3,都不认作不可用。
  it("does not relay exit 3 without the status word", function()
    check.is_nil(availability.child_diagnostic(3, "test_runner: boom\n"))
  end)

  it("does not relay a non-3 exit that mentions the status word", function()
    check.is_nil(availability.child_diagnostic(1, _CHILD_UNAVAILABLE))
  end)
end)
