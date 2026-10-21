-- 直跑入口的解释器预检(#191 故事 3):与 tools/cli.lua 同口径,非 5.4 立即退 1。
if _VERSION ~= "Lua 5.4" then
  io.stderr:write("Lua 5.4 interpreter required; run `lua5.4 tools/cli.lua <子命令>` (found " .. tostring(_VERSION) .. ")\n")
  os.exit(1)
end
require("test.bootstrap").install_package_paths()

local proc_lib = require("foundation.proc")
local parallel_lanes = require("foundation.parallel_lanes")
local sharding = require("foundation.spec_sharding")
local runner_bin = require("packages.test_runner.lua54")
local lane_tools = require("packages.spec_lane.spec_lane_tools")
local availability = require("foundation.tool_availability")

local M = {}

-- worker 工具/平台不可用:退 3,诊断由 CLI 写 stderr;不计 failed。
local function _unavailable_result(diagnostic)
  return { passed = 0, failed = 0, ok = false, exit_code = availability.EXIT_CODE, diagnostic = diagnostic }
end

local _BEHAVIOR_ROOT = "test/behavior"
local _BATCH_TIMEOUT = 600

local function _discover_spec_files(root)
  return sharding.discover_spec_files(root)
end

local _profile_roots = lane_tools.profile_roots

local function _resolve_roots(opts)
  if opts.profile ~= nil then
    return _profile_roots(opts.profile)
  end
  if opts.roots ~= nil then
    return opts.roots
  end
  return { opts.root or _BEHAVIOR_ROOT }
end

local _discover_spec_files_for_roots = sharding.discover_files

local function _file_cost(path)
  return sharding.file_cost(path)
end

local function _build_lanes(files, worker_count)
  local lanes = sharding.build_lpt_lanes(files, worker_count)
  return lanes, #lanes
end

-- #518: behavior 是 slim 关键路径,默认 3 worker 时车道 ~5s 顶到 10s 预算边缘;
-- 实测 6 worker 把车道压到 ~3s,给预算留出余量(可用 EGGY_BEHAVIOR_WORKERS 覆写)。
local function _default_workers()
  return 6
end

local function _resolve_workers(file_count)
  return sharding.resolve_workers("EGGY_BEHAVIOR_WORKERS", file_count, _default_workers())
end

local function _build_lane_args(files)
  -- 默认后端 = 真实 busted 运行器(argv_prefix 返回 { lua5.4,
  -- tools/packages/test_runner/runner.lua })。BUSTED_BIN 已删除。
  local args = {}
  for _, token in ipairs(runner_bin.argv_prefix()) do
    args[#args + 1] = token
  end
  args[#args + 1] = "--helper=test/helper.lua"
  args[#args + 1] = "--output=test/log_warns_handler.lua"
  args[#args + 1] = "--pattern=test_"
  args[#args + 1] = "--"
  for _, f in ipairs(files) do
    args[#args + 1] = f
  end
  return args
end

local function _parse_output(content)
  local result = {
    passed = 0,
    failed = 0,
    failure_lines = {},
    warn_lines = {},
    slow_lines = {},
  }
  if content == nil then
    return result
  end
  local summary_passed = nil
  local summary_failed = nil
  local summary_line = nil
  for line in content:gmatch("[^\n]+") do
    line = line:gsub("\r$", "")
    if line:match("^ok %d") then
      result.passed = result.passed + 1
    elseif line:match("^not ok %d") then
      result.failed = result.failed + 1
      result.failure_lines[#result.failure_lines + 1] = line
    elseif line:match("^not ok %- failed to load ") then
      result.failure_lines[#result.failure_lines + 1] = line
    elseif line:match("^# ") and result.failure_lines[#result.failure_lines]
        and result.failure_lines[#result.failure_lines]:match("^not ok %- failed to load ") then
      result.failure_lines[#result.failure_lines + 1] = line
    elseif line:match("^# BASELINE LEAK") then
      -- 共享端口基线守卫(#217)的点名行:worker 内 errors 计数只影响退出码,
      -- 明细靠这里透传进 failures 段。
      result.failed = result.failed + 1
      result.failure_lines[#result.failure_lines + 1] = line
    elseif line:match("^# WARN ") then
      local text = line:sub(8)
      result.warn_lines[text] = (result.warn_lines[text] or 0) + 1
    elseif line:match("^# SLOW ") then
      result.slow_lines[#result.slow_lines + 1] = line
    elseif line:match("^# RESULT: ") then
      local passed_only = line:match("^# RESULT: (%d+) ok$")
      local passed, failed, errors = line:match("^# RESULT: (%d+) ok .- (%d+) FAIL .- (%d+) error")
      if passed_only ~= nil then
        summary_passed = tonumber(passed_only)
        summary_failed = 0
      elseif passed ~= nil then
        summary_passed = tonumber(passed)
        summary_failed = (tonumber(failed) or 0) + (tonumber(errors) or 0)
        summary_line = line
      end
    end
  end
  if result.passed == 0 and summary_passed ~= nil then
    result.passed = summary_passed
  end
  if result.failed == 0 and (summary_failed or 0) > 0 then
    result.failed = summary_failed
    result.failure_lines[#result.failure_lines + 1] = summary_line or "# RESULT: failed"
  end
  return result
end

-- worker 非零退出且无可解析失败行时(典型:进程崩溃 os.exit(-1)/255),
-- 只报退出码无法定位(#560)。把捕获输出的末尾几行透传进 failures 段。
local _CRASH_EXCERPT_LINES = 15

local function _crash_excerpt(content)
  local lines = {}
  if content == nil then
    return lines
  end
  for line in content:gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    lines[#lines] = nil
  end
  local first = math.max(1, #lines - _CRASH_EXCERPT_LINES + 1)
  local excerpt = {}
  for i = first, #lines do
    excerpt[#excerpt + 1] = lines[i]
  end
  return excerpt
end

local function _print_summary(merged, elapsed, worker_count, label)
  if next(merged.warn_counts) then
    io.write("# warn summary:\n")
    local rows = {}
    for line, count in pairs(merged.warn_counts) do
      rows[#rows + 1] = { line = line, count = count }
    end
    table.sort(rows, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return a.line < b.line
    end)
    for _, row in ipairs(rows) do
      io.write(string.format("#   [non-whitelisted] x%d %s\n", row.count, row.line))
    end
    io.write(string.format("# total non-whitelisted warns: %d\n",
      merged.total_warns))
  end

  if #merged.slow_lines > 0 then
    io.write("# slow summary:\n")
    for _, line in ipairs(merged.slow_lines) do
      io.write(line .. "\n")
    end
    io.write(string.format("# total slow tests: %d\n", #merged.slow_lines))
  end

  local status = merged.failed > 0 and "FAIL" or "PASS"
  io.write(string.format(
    "\n[%s-parallel] %s  %d passed / %d failed  workers=%d  %.1fs\n",
    label, status, merged.passed, merged.failed, worker_count, elapsed
  ))
  io.flush()
end

function M.run(opts)
  opts = opts or {}
  local roots, roots_err = _resolve_roots(opts)
  if roots == nil then
    io.write("[parallel] " .. tostring(roots_err) .. "\n")
    return { passed = 0, failed = 1, ok = false, exit_code = 1 }
  end
  local label = opts.label
    or opts.profile
    or (roots[1] and roots[1]:match("([^/]+)$"))
    or "parallel"

  local files = _discover_spec_files_for_roots(roots)
  if #files == 0 then
    io.write("[" .. label .. "-parallel] no spec files found in " .. table.concat(roots, ",") .. "\n")
    return { passed = 0, failed = 0, ok = true, exit_code = 0 }
  end

  local worker_count = _resolve_workers(#files)
  local env_label = os.getenv("EGGY_BEHAVIOR_WORKERS") or "auto"
  io.write(string.format(
    "[%s-parallel] files=%d workers=%s resolved=%d scheduler=lpt\n",
    label, #files, env_label, worker_count
  ))
  io.flush()

  if worker_count <= 1 then
    io.write("[" .. label .. "-parallel] single worker, running serial\n")
    io.flush()
    -- 串行也跑同一份已发现文件清单(而非把 roots 丢给 runner 再发现一次):
    -- 发现口径唯一,串行/并行跑的集合逐文件一致(#560 曾因此漂移)。
    local result = proc_lib.run_command(_build_lane_args(files))
    local diagnostic = availability.child_diagnostic(result.code, result.output)
    if diagnostic ~= nil then
      return _unavailable_result(diagnostic)
    end
    if result.output and result.output ~= "" then
      io.write(result.output)
      if result.output:sub(-1) ~= "\n" then io.write("\n") end
      io.flush()
    end
    local success = result.ok == true
    return { passed = 0, failed = success and 0 or 1, ok = success, exit_code = success and 0 or 1 }
  end

  local lanes = _build_lanes(files, worker_count)
  local started_at = os.time()

  local lane_specs = {}
  local lane_meta = {}
  for _, lane in ipairs(lanes) do
    if #lane.files > 0 then
      lane_specs[#lane_specs + 1] = {
        label = label .. "_w" .. tostring(lane.index),
        cmd = _build_lane_args(lane.files),
      }
      lane_meta[#lane_meta + 1] = lane
    end
  end

  local run_lanes = opts.run_lanes or parallel_lanes.run
  local _, results = run_lanes(lane_specs, {
    stream = false,
    timeout = _BATCH_TIMEOUT,
  })

  local merged = {
    passed = 0,
    failed = 0,
    failure_lines = {},
    warn_counts = {},
    total_warns = 0,
    slow_lines = {},
  }

  -- 不可用的 worker 不解析、不计 failed,诊断只留一份。
  local diagnostic
  for i, r in ipairs(results) do
    local worker_diagnostic = availability.child_diagnostic(r.exit_code, r.output)
    if worker_diagnostic ~= nil then
      diagnostic = diagnostic or worker_diagnostic
      goto continue
    end
    local parsed = _parse_output(r.output)

    merged.passed = merged.passed + parsed.passed
    merged.failed = merged.failed + parsed.failed
    for _, line in ipairs(parsed.failure_lines) do
      merged.failure_lines[#merged.failure_lines + 1] = line
    end
    for text, count in pairs(parsed.warn_lines) do
      merged.warn_counts[text] = (merged.warn_counts[text] or 0) + count
      merged.total_warns = merged.total_warns + count
    end
    for _, line in ipairs(parsed.slow_lines) do
      merged.slow_lines[#merged.slow_lines + 1] = line
    end

    if (not r.ok or parsed.passed + parsed.failed == 0) and parsed.failed == 0 then
      merged.failed = merged.failed + 1
      merged.failure_lines[#merged.failure_lines + 1] =
        "worker " .. tostring(lane_meta[i].index) .. " exited with code " .. tostring(r.exit_code)
      for _, line in ipairs(_crash_excerpt(r.output)) do
        merged.failure_lines[#merged.failure_lines + 1] = "| " .. line
      end
    end
    ::continue::
  end

  local elapsed = math.max(0, os.time() - started_at)

  if diagnostic ~= nil and merged.failed == 0 then
    io.write(string.format("\n[%s-parallel] UNAVAILABLE  test runner bootstrap unavailable  workers=%d  %.1fs\n",
      label, #lane_specs, elapsed))
    return _unavailable_result(diagnostic)
  end

  if #merged.failure_lines > 0 then
    io.write("\n[" .. label .. "-parallel] failures:\n")
    for _, line in ipairs(merged.failure_lines) do
      io.write("  " .. line .. "\n")
    end
  end

  _print_summary(merged, elapsed, #lane_specs, label)

  return {
    passed = merged.passed,
    failed = merged.failed,
    ok = merged.failed == 0,
    exit_code = merged.failed == 0 and 0 or 1,
  }
end

M._test_support = {
  discover_spec_files = _discover_spec_files,
  discover_spec_files_for_roots = _discover_spec_files_for_roots,
  file_cost = _file_cost,
  build_lanes = _build_lanes,
  parse_output = _parse_output,
  crash_excerpt = _crash_excerpt,
  resolve_workers = _resolve_workers,
  profile_roots = _profile_roots,
}

if arg and arg[0] and arg[0]:find("behavior_parallel", 1, true) then
  local cli_opts = {}
  for i = 1, #arg do
    if arg[i] == "--root" and arg[i + 1] then
      cli_opts.root = arg[i + 1]
    elseif arg[i] == "--profile" and arg[i + 1] then
      cli_opts.profile = arg[i + 1]
    elseif arg[i] == "--label" and arg[i + 1] then
      cli_opts.label = arg[i + 1]
    end
  end
  local result = M.run(cli_opts)
  if result.diagnostic ~= nil then
    io.stderr:write(result.diagnostic)
  end
  os.exit(result.exit_code)
end

return M
