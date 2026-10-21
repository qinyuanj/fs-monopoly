-- luacheck: ignore 143
require("test.bootstrap").install_package_paths()
local luassert = assert
---@diagnostic disable: undefined-global

local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local shell_lib = require("foundation.shell")
-- 通过项目运行器启动真实 busted 子进程，观察输出处理器与退出码。
local runner_bin = require("foundation.lua54")

local project_root = path_lib.normalize_path(env_lib.current_dir())

local function _runner_argv(extra)
  local args = { runner_bin.lua54_bin(), path_lib.join_path(project_root, "tools/packages/test_runner/runner.lua") }
  args[#args + 1] = "--helper=test/helper.lua"
  args[#args + 1] = "--output=test/log_warns_handler.lua"
  for _, value in ipairs(extra or {}) do
    args[#args + 1] = value
  end
  return args
end

local function _cleanup_tmp(tmp_root)
  local ok, err = fs_lib.remove_path(tmp_root)
  if ok == nil then
    error(err)
  end
end

local function _with_tmp(tag, fn)
  local tmp_root = env_lib.make_temp_path("log_warns_handler_" .. tostring(tag or "tmp"), "")
  _cleanup_tmp(tmp_root)
  local ok, err = xpcall(function()
    fn(tmp_root)
  end, debug.traceback)
  _cleanup_tmp(tmp_root)
  if not ok then
    error(err)
  end
end

-- 专属临时清单登记必失败的真实 busted spec；保留诊断与 warning 文本。
local function _write_noisy_spec(path)
  local ok, err = fs_lib.write_file(path, table.concat({
    "local luassert = assert",
    "describe(\"TestNoisy\", function()",
    "it(\"test_xxx\", function()",
    "  print('0 [info] noisy info line')",
    "  print('plain diagnostic line')",
    "  print('0 [warn] custom warning line')",
    "  luassert.is_true(false, 'boom failure')",
    "end)",
    "end)",
    "",
  }, "\n"))
  luassert.is_true(ok, tostring(err))
end

local function _run_with_handler(spec_path, extra_args)
  local args = _runner_argv(extra_args)
  args[#args + 1] = spec_path
  return proc_lib.run_command(args, { cwd = project_root })
end

local function _run_verbose_drop_info(spec_path)
  local args = _runner_argv({ "-Xoutput", "drop-info" })
  args[#args + 1] = spec_path
  local run_command = shell_lib.build_command(args)
  return proc_lib.run_command("EGGY_TEST_VERBOSE=1 " .. run_command, { cwd = project_root })
end

describe("TestLogWarnsHandler", function()

it("test_preserves_captured_info_lines_by_default", function()
  _with_tmp("default", function(tmp_root)
    local spec_path = path_lib.join_path(tmp_root, "test_noisy.lua")
    _write_noisy_spec(spec_path)

    local result = _run_with_handler(spec_path)

    luassert.is_false(result.ok)
    luassert.truthy(result.output:find("0 %[info%] noisy info line"), result.output)
    luassert.truthy(result.output:find("plain diagnostic line", 1, true))
    luassert.truthy(result.output:find("# WARN 0 [warn] custom warning line", 1, true))
    luassert.truthy(result.output:find("boom failure", 1, true))
  end)
end)

it("test_drops_captured_info_lines_when_requested", function()
  _with_tmp("drop_info", function(tmp_root)
    local spec_path = path_lib.join_path(tmp_root, "test_noisy.lua")
    _write_noisy_spec(spec_path)

    local result = _run_with_handler(spec_path, { "-Xoutput", "drop-info" })

    luassert.is_false(result.ok)
    luassert.is_nil(result.output:find("0 %[info%] noisy info line"))
    luassert.truthy(result.output:find("plain diagnostic line", 1, true))
    luassert.truthy(result.output:find("# WARN 0 [warn] custom warning line", 1, true))
    luassert.truthy(result.output:find("boom failure", 1, true))
    luassert.truthy(result.output:find("1 FAIL", 1, true))
  end)
end)

it("test_does_not_drop_info_lines_in_verbose_mode", function()
  _with_tmp("verbose_drop_info", function(tmp_root)
    local spec_path = path_lib.join_path(tmp_root, "test_noisy.lua")
    _write_noisy_spec(spec_path)

    local result = _run_verbose_drop_info(spec_path)

    luassert.is_false(result.ok)
    luassert.truthy(result.output:find("0 %[info%] noisy info line"), result.output)
    luassert.truthy(result.output:find("not ok 1 -", 1, true))
  end)
end)


end)
