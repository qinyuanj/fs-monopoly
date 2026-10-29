---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/foundation/test/test_tool_cli.lua") end

require("test.bootstrap").install_package_paths()

local check = require("luassert")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local tool_cli = require("foundation.tool_cli")


-- 每个用例一间临时 fixture 仓:package.path 挂上临时目录,teardown 时还原并
-- 清掉 require 缓存,避免用例间串扰。
local function _with_fixture_root(body)
  local root = env_lib.make_temp_path("tool_cli_spec", "")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(root))
  local original_path = package.path
  package.path = package.path .. ";" .. root .. "/?.lua"
  local ok, err = pcall(body, root)
  package.path = original_path
  package.loaded["fixture_runner"] = nil
  fs_lib.remove_path(root)
  if not ok then
    error(err, 2)
  end
end

describe("tool cli", function()
it("normalize exit code passes numbers through", function()
  check.equal(0, tool_cli.normalize_exit_code(0))
  check.equal(1, tool_cli.normalize_exit_code(1))
  check.equal(2, tool_cli.normalize_exit_code(2))
end)

it("normalize exit code maps truthy and falsy", function()
  check.equal(0, tool_cli.normalize_exit_code(true))
  check.equal(1, tool_cli.normalize_exit_code(false))
  check.equal(1, tool_cli.normalize_exit_code(nil))
end)

it("run passes caller env through untouched", function()
  _with_fixture_root(function(root)
    -- fixture 故意带 env 字段:断言 adapter 对它视而不见(不替 runner 合并)
    check.is_true(fs_lib.write_file(path_lib.join_path(root, "fixture_runner.lua"), table.concat({
      "local M = { env = { from_runner = 'runner', shared = 'runner-default' } }",
      "function M.run(args, env)",
      "  M.captured = { args = args, env = env }",
      "  return 3",
      "end",
      "return M",
      "",
    }, "\n")))

    local caller_env = { shared = "caller", from_caller = "yes" }
    local code = tool_cli.run(
      { runner_module = "fixture_runner", runner_script = "missing/runner.lua" },
      { "a", "b" },
      caller_env
    )

    check.equal(3, code)
    local captured = require("fixture_runner").captured
    check.same({ "a", "b" }, captured.args)
    -- merge 职责在 runner 侧(#323):cli adapter 原样透传,不替 runner 合并
    check.equal(caller_env, captured.env)
  end)
end)

it("run normalizes boolean runner results", function()
  _with_fixture_root(function(root)
    check.is_true(fs_lib.write_file(path_lib.join_path(root, "fixture_runner.lua"), table.concat({
      "local M = {}",
      "function M.run() return M.result end",
      "return M",
      "",
    }, "\n")))
    local runner = require("fixture_runner")

    runner.result = true
    check.equal(0, tool_cli.run({ runner_module = "fixture_runner", runner_script = "missing" }, {}, nil))
    runner.result = false
    check.equal(1, tool_cli.run({ runner_module = "fixture_runner", runner_script = "missing" }, {}, nil))
  end)
end)

it("run falls back to subprocess when module missing", function()
  _with_fixture_root(function(root)
    local script = path_lib.join_path(root, "fixture_script.lua")
    check.is_true(fs_lib.write_file(script, "os.exit(tonumber(arg[1]))\n"))

    local code = tool_cli.run(
      { runner_module = "no_such_module_xyz", runner_script = script },
      { "7" },
      nil
    )

    check.equal(7, code)
  end)
end)

it("forward subprocess passes args and exit code", function()
  _with_fixture_root(function(root)
    local script = path_lib.join_path(root, "fixture_script.lua")
    check.is_true(fs_lib.write_file(script, "assert(arg[1] == 'has space')\nos.exit(5)\n"))

    check.equal(5, tool_cli.forward_subprocess(script, { "has space" }))
  end)
end)

end)
