---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/test_runner/test/test_backend_contract.lua") end
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local proc = require("foundation.proc")
local lua54 = require("foundation.lua54")
local env = require("foundation.env")
local fs = require("foundation.fs")
local spec_sharding = require("foundation.spec_sharding")
local root = require("foundation.bootstrap").resolve(debug.getinfo(1, "S").source).repo_root
local fixtures = "test/fixtures/busted_backend/"
local function run(files, helper)
  local command = { lua54.lua54_bin(), root .. "/tools/packages/test_runner/runner.lua", "--output=TAP" }
  if helper then command[#command + 1] = "--helper=test/helper.lua" end
  command[#command + 1] = "--"
  for _, file in ipairs(files) do command[#command + 1] = fixtures .. file .. ".lua" end
  return proc.run_command(command)
end

describe("real busted execution", function()
  it("empty registered suite fails", function()
    local suite_root = env.make_temp_path("zero_cases_73", "")
    check.truthy(fs.write_file(suite_root .. "/test_empty.lua", "return {}\n"))
    local result = proc.run_command({ "lua", "tools/packages/test_runner/runner.lua", "--", suite_root .. "/test_empty.lua" })
    check.truthy(fs.remove_path(suite_root))
    check.truthy(not result.ok and result.output:find("cases=0", 1, true), result.output)
  end)

  it("reports one reconciled counts line", function()
    local result = run({ "passing" })
    check.equal(0, result.code, result.output)
    check.matches("# COUNTS: files=1 cases=2 passed=2 failed=0 errors=0", result.output, 1, true)
    local _, count = result.output:gsub("# COUNTS:", "")
    check.equal(1, count, result.output)
  end)
  it("keeps every TAP line intact when stderr shares stdout", function()
    local result = run({ "merged_stderr" })
    check.equal(0, result.code, result.output)
    local output = "\n" .. result.output:gsub("\r\n", "\n")
    for i = 1, 200 do
      local expected = string.format("ok %d - merged stderr case %d %s", i, i, string.rep("x", 40))
      check.matches("\n" .. expected .. "\n", output, 1, true)
    end
    check.matches("\n# COUNTS: files=1 cases=200 passed=200 failed=0 errors=0\n", output, 1, true)
  end)
  it("keeps failure TAP and diagnostics intact when stderr shares stdout", function()
    local result = run({ "merged_stderr_failure" })
    check.equal(1, result.code, result.output)
    local output = "\n" .. result.output:gsub("\r\n", "\n")
    for i = 1, 200 do
      local name = string.format("case %d %s", i, string.rep("x", 40))
      check.matches("\n" .. string.format("not ok %d - merged stderr failure %s", i, name) .. "\n", output, 1, true)
      check.matches("\n# (string) '" .. string.format("actual %d %s", i, string.rep("z", 40)) .. "'\n", output, 1, true)
      check.matches("\n# (string) '" .. string.format("expected %d %s", i, string.rep("y", 40)) .. "'\n", output, 1, true)
    end
    local _, sources = output:gsub("\n# test/fixtures/busted_backend/merged_stderr_failure%.lua @ %d+\n", "")
    local _, messages = output:gsub("\n# Failure message: [^\n]*Expected objects to be equal%.\n", "")
    local _, passed_in = output:gsub("\n# Passed in:\n", "")
    local _, expected = output:gsub("\n# Expected:\n", "")
    check.equal(200, sources, result.output)
    check.equal(200, messages, result.output)
    check.equal(200, passed_in, result.output)
    check.equal(200, expected, result.output)
    check.matches("\n# COUNTS: files=1 cases=200 passed=0 failed=200 errors=0\n", output, 1, true)
  end)
  -- #107:--durations-out 落每文件实测秒数(spec_lane 实测时长缓存的数据源),
  -- 一行一个文件(格式归 spec_sharding.parse_durations);TAP 与计数不受影响。
  it("durations out records one measured line per spec file", function()
    local out = env.make_temp_path("spec_durations", ".tsv")
    local command = { lua54.lua54_bin(), root .. "/tools/packages/test_runner/runner.lua", "--output=TAP",
      "--durations-out=" .. out, "--", fixtures .. "passing.lua", fixtures .. "failing.lua" }
    local result = proc.run_command(command)
    local text = fs.read_raw(out) or ""
    fs.remove_path(out)
    check.matches("cases=3 passed=2 failed=1 errors=0", result.output, 1, true)
    local seen = spec_sharding.parse_durations(text)
    check.is_not_nil(seen[fixtures .. "passing.lua"], text)
    check.is_not_nil(seen[fixtures .. "failing.lua"], text)
  end)
  it("nested hooks replay rng and restore ports after teardown", function()
    local result = run({ "test/behavior/lifecycle" }, true)
    check.equal(0, result.code, result.output)
    check.matches("cases=2 passed=2 failed=0 errors=0", result.output, 1, true)
  end)
  it("teardown leak fails and is restored for next case", function()
    local result = run({ "test/behavior/leak" }, true)
    check.equal(1, result.code, result.output)
    check.matches("# BASELINE LEAK:", result.output, 1, true)
    local compressed = require("foundation.tap_summary").compress(result.output)
    check.matches("# BASELINE LEAK:", compressed, 1, true)
    check.matches("errors=1", compressed, 1, true)
    check.matches("cases=2 passed=2 failed=0 errors=1", result.output, 1, true)
  end)
  it("actual failure and empty busted are nonzero", function()
    for _, name in ipairs({ "failing", "empty" }) do
      local result = run({ name })
      check.equal(1, result.code, result.output)
      if name == "failing" then check.matches("cases=1 passed=0 failed=1 errors=0", result.output, 1, true)
      else check.matches("empty result", result.output, 1, true) end
    end
  end)
  it("rejects missing and duplicate file identities", function()
    for _, files in ipairs({ { "missing" }, { "passing", "passing" } }) do
      local result = run(files)
      check.equal(1, result.code, result.output)
      check.matches("identity", result.output, 1, true)
    end
  end)
  it("failed setup and teardown are errors and restore baseline", function()
    local result = run({ "test/behavior/hook_errors" }, true)
    check.equal(1, result.code, result.output)
    for _, text in ipairs({ "victim still sees shared ports", "# BASELINE LEAK:", "setup exploded",
      "teardown exploded", "files=1 cases=3 passed=1 failed=0 errors=4" }) do
      check.matches(text, result.output, 1, true)
    end
  end)
  it("controlled provenance rejects preloaded fake busted", function()
    local script = 'dofile("tools/foundation/bootstrap.lua").install("tools/cli.lua"); package.loaded["busted.core"]={}; require("packages.test_runner.cache_loader").install("' .. root .. '")'
    local result = proc.run_command({ lua54.lua54_bin(), "-e", script })
    check.equal(1, result.code, result.output)
    check.matches("unverified preloaded module: busted.core", result.output, 1, true)
  end)
  it("discovers unique files in actual profiles", function()
    local profiles = dofile(root .. "/tools/packages/spec_lane/spec_profiles.lua")
    local seen, count = {}, 0
    for _, name in ipairs({ "contract", "guards", "behavior", "tooling" }) do
      for _, directory in ipairs(profiles[name].ROOT) do
        for _, file in ipairs(require("foundation.spec_sharding").discover_spec_files(directory)) do
          check.is_nil(seen[file], file)
          seen[file], count = true, count + 1
        end
      end
    end
    check.is_true(count > 0)
  end)
  it("one runtime error is counted once", function()
    local result = run({ "runtime_error" })
    check.equal(1, result.code, result.output)
    check.matches("body exploded", result.output, 1, true)
    check.matches("cases=1 passed=0 failed=0 errors=1", result.output, 1, true)
  end)
  it("cross file modules keep identity and explicit patch restoration", function()
    local result = run({ "polluter", "victim" })
    check.equal(0, result.code, result.output)
    check.matches("files=2 cases=2 passed=2 failed=0 errors=0", result.output, 1, true)
  end)
  it("pure text file list rejects empty missing and executable data", function()
    local list = env.make_temp_path("busted_file_list", ".txt")
    for _, sample in ipairs({ { "", "empty spec file list" }, { "\n", "invalid file identity" },
      { "missing.lua\n", "missing file identity" }, { "bad\0.lua\n", "invalid file identity" },
      { "notes.txt\n", "invalid file identity" },
      { "error('file list must not execute')\n", "invalid file identity" } }) do
      check.truthy(fs.write_file(list, sample[1]))
      local result = proc.run_command({ lua54.lua54_bin(), root .. "/tools/packages/test_runner/runner.lua",
        "--pattern=^no_match", "--file-list=" .. list })
      check.equal(1, result.code, result.output)
      check.matches(sample[2], result.output, 1, true)
    end
  end)
  it("rejects an empty file beside passing cases", function()
    local result = run({ "passing", "empty" })
    check.equal(1, result.code, result.output)
    check.matches("empty spec file: " .. fixtures .. "empty.lua", result.output, 1, true)
  end)
end)
