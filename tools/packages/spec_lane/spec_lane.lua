#!/usr/bin/env lua5.4
-- 直跑入口的解释器预检(#191 故事 3):与 tools/cli.lua 同口径,非 5.4 立即退 1。
if _VERSION ~= "Lua 5.4" then
  io.stderr:write("Lua 5.4 interpreter required; run `lua5.4 tools/cli.lua <子命令>` (found " .. tostring(_VERSION) .. ")\n")
  os.exit(1)
end
local _self = debug.getinfo(1, "S").source or "@tools/packages/spec_lane/spec_lane.lua"
local _sb = dofile(_self:gsub("\\", "/"):gsub("^@", ""):match("^(.*)/[^/]+$")
  .. "/../../foundation/script_bootstrap.lua")
local bootstrap_env, bootstrap = _sb.install(_self)

local function _normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local proc_lib = require("foundation.proc")
local tap_summary = require("foundation.tap_summary")
local tool_availability = require("foundation.tool_availability")
local parallel_lanes = require("foundation.parallel_lanes")
local sharding = require("foundation.spec_sharding")
local lane_tools = require("packages.spec_lane.spec_lane_tools")
local lane_args = require("packages.spec_lane.spec_lane_args")
local evidence = require("packages.spec_lane.spec_evidence")
local runner_bin = require("packages.test_runner.lua54")

local M = {}

-- 内置文件分片（与 behavior_parallel 共用 packages/test_runner）：
-- 命名 profile 的文件数超过阈值时,按文件边界拆成 N 条 runner 子进程 lane
-- 并行（不拆文件内顺序）；窄目录点跑（--profile <目录>）、文件数少、
-- worker=1、--verbose、--serial 一律走原单进程路径,命令形态逐字节不变。
-- CLI 默认分片并行(#107 恢复;#73 迁移期安全网曾默认 --serial):实测
-- behavior 45.8s → 18.5s、tooling 230.1s → 85.5s(w=3,热时长缓存)。阈值 30:
-- 每 lane 收容进程固定开销约 3s,contract(22 文件)串行 4.0s / 分片 7.0s,
-- 保持串行;guards(17 文件)耗时集中在两个动态生成套件文件,分片拆不动。
local _SHARD_THRESHOLD = 30
local _DEFAULT_WORKERS = 3

-- profile -> 发现根:命名 profile 取 spec_profiles.lua 的 ROOT;目录点跑就是
-- 目录本身;两者都不是(未知 profile)返回 nil,交给串行路径让 runner 报错。
local function _profile_roots(profile)
  if fs_lib.is_dir(profile) then
    return { profile }
  end
  return lane_tools.profile_roots(profile)
end

local _profile_config = lane_tools.profile_config
local _discover_files = sharding.discover_files

-- worker 数:options.workers 显式覆写(测试注入用);否则 EGGY_SPEC_LANE_WORKERS
-- 环境变量(语义对齐 EGGY_BEHAVIOR_WORKERS / EGGY_COVERAGE_WORKERS),默认 3,
-- clamp 到文件数、下限 1。
local function _resolve_workers(file_count, options)
  if options ~= nil and options.workers ~= nil then
    return math.max(1, options.workers)
  end
  return sharding.resolve_workers("EGGY_SPEC_LANE_WORKERS", file_count, _DEFAULT_WORKERS)
end

-- 分片 lane 命令(behavior_parallel 同款形态):--output=TAP 是 spec_lane 的
-- 固定契约,helper/pattern 从 profile config 取值,durations_out 是本 lane
-- 实测时长落点,`--` 后是显式文件清单。
local function _build_shard_cmd(profile, files, durations_out)
  local cfg = _profile_config(profile)
  local args = {}
  for _, token in ipairs(runner_bin.argv_prefix()) do
    args[#args + 1] = token
  end
  args[#args + 1] = "--output=TAP"
  if cfg.helper ~= nil then
    args[#args + 1] = "--helper=" .. cfg.helper
  end
  args[#args + 1] = "--pattern=" .. (cfg.pattern or "test_")
  args[#args + 1] = "--durations-out=" .. durations_out
  args[#args + 1] = "--"
  for _, f in ipairs(files) do
    args[#args + 1] = f
  end
  return args
end

-- 实测时长缓存(#107):基线实测 tooling 按 it 计数分 3 lane 为 112.8/83.6/72.6s
-- 失衡(单文件 it 数与墙钟无关),改按上次实测秒数做 LPT。缓存落仓内生成物目录
-- tmp/(gitignored、由 clean 清理),键为仓库相对路径;首次运行无缓存仍按 it 计数。
-- 每 lane 经 runner --durations-out 落本次每文件秒数,跑完合并回缓存。
local function _cache_path(profile)
  return bootstrap_env.repo_root .. "/tmp/spec_durations/" .. profile .. ".tsv"
end

local function _repo_relative(file)
  local normalized = _normalize_path(file)
  local prefix = _normalize_path(bootstrap_env.repo_root) .. "/"
  if normalized:sub(1, #prefix):lower() == prefix:lower() then return normalized:sub(#prefix + 1) end
  return normalized
end

local function _read_durations(path)
  local durations = {}
  for file, seconds in pairs(sharding.parse_durations(fs_lib.read_raw(path))) do
    durations[_repo_relative(file)] = seconds
  end
  return durations
end

-- 缓存秒数映射到本次发现的文件路径;一个都没命中返回 nil(退回 it 计数)。
local function _load_durations(profile, files)
  local cached = _read_durations(_cache_path(profile))
  local durations, hit = {}, false
  for _, file in ipairs(files) do
    local seconds = cached[_repo_relative(file)]
    if seconds then durations[file], hit = seconds, true end
  end
  return hit and durations or nil
end

-- 合并只保留本次发现清单内的文件(已删/改名文件的旧条目随之淘汰);缓存
-- 写失败只告警,不改退出码——缓存只影响下次分配的均衡度,不影响正确性。
local function _merge_durations(profile, files, measured_paths)
  local cache = _cache_path(profile)
  local cached, current, merged, updated = _read_durations(cache), {}, {}, false
  for _, file in ipairs(files) do
    local key = _repo_relative(file)
    current[key], merged[key] = true, cached[key]
  end
  for _, out in ipairs(measured_paths) do
    for file, seconds in pairs(_read_durations(out)) do
      if current[file] then merged[file], updated = seconds, true end
    end
    fs_lib.remove_path(out)
  end
  if not updated then return end
  local ok, err = fs_lib.write_file(cache, sharding.format_durations(merged))
  if not ok then
    io.stderr:write("[spec-lane] warning: duration cache write failed: " .. tostring(err) .. "\n")
  end
end

-- runner 子进程工具/平台不可用:诊断原样转 stderr,不报 failed。
local function _unavailable_result(diagnostic)
  return { stdout = "", stderr = diagnostic, code = tool_availability.EXIT_CODE,
    status = "unavailable", passed = 0, failed = 0 }
end

-- 时长缓存让 lane 分配随运行变化;失败时打印本次 lane → 文件清单(执行顺序)。
local function _lane_listing(lane_specs)
  local lines = { "# lane 分配(执行顺序);复现请用 --serial 或按清单点跑:" }
  for _, spec in ipairs(lane_specs) do
    lines[#lines + 1] = spec.label .. ":"
    for _, file in ipairs(spec.files) do lines[#lines + 1] = "  " .. file end
  end
  return table.concat(lines, "\n") .. "\n"
end

-- #130:计数真源是 runner 进程内的 COUNTS,不是 TAP 的 ok 行数。lane 把
-- stdout/stderr 合到同一句柄,stderr 会插进 stdout 两次冲刷之间把 TAP 行切开,
-- ok 行口径会漏计;COUNTS 由计数器直接生成,不受串流影响。这里把两种口径都算出来:
-- 摘要与退出码用 COUNTS,TAP 计数只做交叉核对,不一致就点名(不再静默差 1)。
local function _authoritative(aggregated)
  if aggregated.counts == nil then return nil end
  return {
    passed = aggregated.counts.passed,
    failed = aggregated.counts.failed + aggregated.counts.errors,
  }
end

local function _count_diagnostics(aggregated, include_counts)
  local lines = {}
  if include_counts and aggregated.counts ~= nil then
    lines[#lines + 1] = evidence.format_counts(aggregated.counts)
  end
  if #aggregated.missing > 0 then
    lines[#lines + 1] = "[spec-lane] COUNTS missing(这些 lane 没有可重算的计数): "
      .. table.concat(aggregated.missing, ", ")
  end
  local mismatch = evidence.mismatch_line(aggregated.counts, aggregated.tally)
  if mismatch ~= nil then lines[#lines + 1] = mismatch end
  if #lines == 0 then return "" end
  return table.concat(lines, "\n") .. "\n"
end

-- 测量证据(#130):原始输出逐 lane 落盘 + 汇总值,事后 `spec-lane --recount <dir>`
-- 只凭目录重算并核对。写失败只告警,不把测试结论改成证据目录的结论。
local function _write_evidence(options, spec)
  if options.evidence_dir == nil then return end
  local ok, err = evidence.write(options.evidence_dir, spec)
  if not ok then
    io.stderr:write("[spec-lane] warning: evidence write failed: " .. tostring(err) .. "\n")
  end
end

-- 分片路径:每 lane 一条 runner 子进程(run_lanes 注入替身,默认 parallel_lanes,
-- stream=false 收集),按 lane 顺序聚合各 worker 的 TAP 后整段交给
-- tap_summary.compress —— 失败明细与串行路径一致,计数与退出码以各 lane 的
-- COUNTS 合计为准(#130),ok 编号跨 worker 重排不影响计数。任何 lane 非零退出
-- 都算失败(与串行 result.code 语义对齐)。
local function _run_sharded(options, profile, files, spawn_env)
  local run_lanes = options.run_lanes or parallel_lanes.run
  local worker_count = _resolve_workers(#files, options)
  local lane_specs, measured_paths = {}, {}
  for _, lane in ipairs(sharding.build_lpt_lanes(files, worker_count, _load_durations(profile, files))) do
    if #lane.files > 0 then
      local out = env_lib.make_temp_path("spec_durations", ".tsv")
      measured_paths[#measured_paths + 1] = out
      lane_specs[#lane_specs + 1] = {
        label = profile .. "_w" .. tostring(lane.index),
        cmd = _build_shard_cmd(profile, lane.files, out),
        files = lane.files,
      }
    end
  end

  local _, results = run_lanes(lane_specs, { stream = false, env = spawn_env })
  _merge_durations(profile, files, measured_paths)

  -- 不可用的 lane 不并入 TAP、不算失败;其余 lane 全过时整体报不可用,
  -- 诊断只转一份。混有真实失败仍退 1(#131)。
  local raw_parts = {}
  local entries = {}
  local code = 0
  local diagnostic
  for i, r in ipairs(results) do
    local lane_diagnostic = tool_availability.child_diagnostic(r.exit_code, r.output)
    if lane_diagnostic ~= nil then
      diagnostic = diagnostic or lane_diagnostic
    else
      if not r.ok then
        code = 1
      end
      local out = tostring(r.output or ""):gsub("%s+$", "")
      if out ~= "" then
        raw_parts[#raw_parts + 1] = out
      end
      -- 与 TAP 同口径:不可用 lane 也不进 COUNTS 聚合与证据汇总(#131/#130)。
      entries[#entries + 1] = { label = r.label or lane_specs[i].label, raw = r.output,
        files = lane_specs[i].files }
    end
  end
  local aggregated = evidence.aggregate(entries)
  local authoritative = _authoritative(aggregated)
  local compressed, tap_passed, tap_failed = M.compress_tap(table.concat(raw_parts, "\n"), authoritative)
  local passed = authoritative and authoritative.passed or tap_passed
  local failed = authoritative and math.max(authoritative.failed, tap_failed) or tap_failed
  if failed > 0 and code == 0 then
    code = 1
  end
  if diagnostic ~= nil and code == 0 then
    return _unavailable_result(diagnostic)
  end
  if code ~= 0 then
    compressed = compressed .. _lane_listing(lane_specs)
  end
  _write_evidence(options, { profile = profile, mode = "sharded", exit_code = code, lanes = entries })
  return { stdout = compressed .. _count_diagnostics(aggregated, true),
    code = code, passed = passed, failed = failed }
end

function M.parse_args(args)
  return lane_args.parse(args)
end

function M.compress_tap(output, authoritative)
  return tap_summary.compress(output, authoritative)
end

function M.run(options)
  options = options or {}

  -- 默认后端 = 真实 busted 运行器(argv_prefix 返回 { lua5.4,
  -- tools/packages/test_runner/runner.lua }）。--busted-bin / BUSTED_BIN 已删除，
  -- PATH 无 busted,迁移已完成)。
  local prefix = runner_bin.argv_prefix()
  local run_command = options.run_command or proc_lib.run_command

  -- #124:工具发现一次解析后随 spawn 导出;作为 verify 车道运行时进程环境已带
  -- 导出值,这里的解析只是复核。子进程树继承后不再各自重复 where/luarocks 探测。
  local spawn_env = bootstrap.tool_discovery_env()

  -- 分片判定:命名 profile(非目录窄点跑)、文件数超阈值、worker > 1、非
  -- --verbose 才走并行;否则原单进程路径。
  local roots = _profile_roots(options.profile)
  local files = {}
  if roots ~= nil then
    files = _discover_files(roots, _profile_config(options.profile).pattern or "test_")
  end
  local shardable = roots ~= nil
    and fs_lib.is_dir(options.profile) ~= true
    and #files > _SHARD_THRESHOLD
    and _resolve_workers(#files, options) > 1
    and options.verbose ~= true
    and options.serial ~= true

  if not shardable then
    local command = {}
    for _, token in ipairs(prefix) do
      command[#command + 1] = token
    end
    command[#command + 1] = "--output=TAP"
    command[#command + 1] = "--run"
    command[#command + 1] = options.profile
    local result = run_command(command, spawn_env ~= nil and { env = spawn_env } or nil)
    local raw = tostring(result.output or "")

    local code = result.code or (result.ok and 0 or 1)
    local diagnostic = tool_availability.child_diagnostic(code, raw)
    if diagnostic ~= nil then
      return _unavailable_result(diagnostic)
    end
    local entries = { { label = options.profile, raw = raw } }
    local aggregated = evidence.aggregate(entries)
    local authoritative = _authoritative(aggregated)
    local compressed, tap_passed, tap_failed = M.compress_tap(raw, authoritative)
    local passed = authoritative and authoritative.passed or tap_passed
    local failed = authoritative and math.max(authoritative.failed, tap_failed) or tap_failed
    if (failed > 0 or passed == 0) and code == 0 then code = 1 end
    _write_evidence(options, { profile = options.profile, mode = "serial", exit_code = code, lanes = entries })
    local counts = aggregated.counts and evidence.format_counts(aggregated.counts)
      or raw:match("# COUNTS: [^\r\n]+")
    local stdout
    if options.verbose then
      stdout = raw
      local diagnostics = _count_diagnostics(aggregated, false)
      if diagnostics ~= "" then
        if stdout ~= "" and stdout:sub(-1) ~= "\n" then stdout = stdout .. "\n" end
        stdout = stdout .. diagnostics
      end
    else
      stdout = compressed .. (counts and counts .. "\n" or "") .. _count_diagnostics(aggregated, false)
    end
    -- 一个用例都没解析出来就失败(典型:依赖预检错误),摘要只剩「0 passed」,
    -- 原样附上子进程输出交代原因(#131)。
    if code ~= 0 and passed + failed == 0 and not options.verbose then
      stdout = stdout .. raw .. (raw:sub(-1) == "\n" and "" or "\n")
    end
    return { stdout = stdout, code = code, passed = passed, failed = failed, discovered = #files }
  end

  return _run_sharded(options, options.profile, files, spawn_env)
end

-- 仅凭证据目录重算(#130):原始 .tap → COUNTS 合计 + TAP 交叉核对,与当时写下的
-- 汇总值逐项比对;对不上就是证据被改过或当时汇总不可信,退 1。
function M.recount(dir)
  local result, err = evidence.recount(dir)
  if result == nil then
    return { stdout = "[spec-lane] recount status=mismatch " .. tostring(err) .. "\n", code = 1 }
  end
  local lines = {
    "[spec-lane] recount dir=" .. tostring(dir)
      .. " profile=" .. tostring(result.profile) .. " mode=" .. tostring(result.mode),
    result.counts and evidence.format_counts(result.counts) or "# COUNTS: unavailable",
    string.format("tap passed=%d failed=%d", result.tally.passed, result.tally.failed),
    result.match and "status=match" or ("status=mismatch " .. tostring(result.detail)),
  }
  return { stdout = table.concat(lines, "\n") .. "\n", code = result.match and 0 or 1 }
end

function M.main(args)
  local options, err = M.parse_args(args)
  if not options then
    io.stderr:write(lane_args.usage())
    io.stderr:write(tostring(err) .. "\n")
    return 2
  end
  if options.help then
    io.write(lane_args.usage())
    return 0
  end
  if options.recount ~= nil then
    local recount = M.recount(options.recount)
    io.write(recount.stdout)
    return recount.code
  end
  local result = M.run(options)
  io.write(result.stdout)
  if result.stderr ~= nil then
    io.stderr:write(result.stderr)
  end
  return result.code
end

if ... == "packages.spec_lane.spec_lane" then
  return M
end

os.exit(M.main(arg or {}))
