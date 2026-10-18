---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/spec_lane/test/test_spec_lane.lua") end
require("test.bootstrap").install_package_paths()

local check = require("luassert")
local spec_lane = require("packages.spec_lane.spec_lane")
local lane_tools = require("packages.spec_lane.spec_lane_tools")
local spec_evidence = require("packages.spec_lane.spec_evidence")

local function _all_pass_tap()
  return table.concat({
    "ok 1 - first thing works",
    "ok 2 - second thing works",
    "ok 3 - third thing works",
    "1..3",
  }, "\n") .. "\n"
end

-- Public argument, runner, sharding and discovery cases.

local function
parse_args_requires_profile()
  local opts, err = spec_lane.parse_args({})
  check.is_nil(opts)
  check.truthy(tostring(err):find("missing --profile", 1, true))
end

local function
parse_args_parses_profile()
  local opts = spec_lane.parse_args({ "--profile", "contract" })
  check.equal("contract", opts.profile)
  check.is_false(opts.verbose)
end

-- #107:CLI 默认恢复分片并行(#73 迁移期安全网曾默认 --serial 关闭分片;
-- 基线实测 behavior 45.8s 串行 → 20.2s 分片)。--serial 仍是显式逃生舱。
local function
parse_args_defaults_to_sharding_eligible()
  local opts = spec_lane.parse_args({ "--profile", "contract" })
  check.is_false(opts.serial)
end

local function
parse_args_parses_verbose_alongside_profile()
  local opts = spec_lane.parse_args({ "--profile", "guards", "--verbose" })
  check.equal("guards", opts.profile)
  check.is_true(opts.verbose)
end

-- --busted-bin 不再是合法选项。
local function
parse_args_rejects_removed_busted_bin_escape_hatch()
  local opts, err = spec_lane.parse_args({ "--profile", "contract", "--busted-bin", "custom-busted" })
  check.is_nil(opts)
  check.truthy(tostring(err):find("unknown option: --busted-bin", 1, true))
end

-- compress_tap 是 foundation.tap_summary.compress 的纯转发(#361 P5):行为面
-- 全在 test_tap_summary.lua,这里只留一个透传冒烟钉住接线没断。
local function
compress_tap_collapses_all_pass_tap_to_single_passed_line()
  local out, passed, failed = spec_lane.compress_tap(_all_pass_tap())
  check.equal("3 passed\n", out)
  check.equal(3, passed)
  check.equal(0, failed)
end

-- 不再支持 busted_bin 单 token 覆写，命令
-- 前缀恒为 argv_prefix 默认值({ lua5.4, test_runner/runner.lua })。workers=1 强制单进程
-- 串行路径(分片判定要求 worker > 1 且 profile 文件数超过阈值)。
local function
run_defaults_to_explicit_real_busted_runner()
  local captured
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    run_command = function(command)
      captured = command
      return { ok = true, code = 0, output = _all_pass_tap() }
    end,
  })

  check.truthy(tostring(captured[2]):find("test_runner/runner%.lua"))
  check.equal("--output=TAP", captured[3])
  check.equal("--run", captured[4])
  check.equal("contract", captured[5])
  check.equal(0, result.code)
  check.equal("3 passed\n[spec-lane] COUNTS missing(这些 lane 没有可重算的计数): contract\n", result.stdout)
end

-- #124:runner spawn 带上一次解析的工具发现环境(LUA54_BIN 全路径 +
-- MONOPOLY_LUAROCKS_EXE),子进程树继承后不再逐进程 where 探测;本机解析不出
-- luarocks 时导出为 nil,不传 options(行为与旧版一致),测试两种形态都接受。
local function
runner_spawn_carries_tool_discovery_env()
  local captured_options
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    run_command = function(command, options)
      captured_options = options
      return { ok = true, code = 0, output = _all_pass_tap() }
    end,
  })

  check.equal(0, result.code)
  -- 两种形态都必须与本机解析结果一致,不允许“没传就算过”。
  local expected = dofile("tools/foundation/bootstrap.lua").tool_discovery_env()
  if expected == nil then
    check.is_nil(captured_options)
  else
    check.truthy(tostring(captured_options.env.LUA54_BIN):find("[/\\]") ~= nil)
    check.truthy(tostring(captured_options.env.MONOPOLY_LUAROCKS_EXE):match("luarocks%.exe$") ~= nil)
  end
end

-- #107:分片固定开销(每 lane 一个 PowerShell 收容进程)实测约 3s,contract
-- (22 文件)串行 4.0s / 分片 7.0s——小 profile 低于阈值(30)保持单进程。
local function
small_profile_below_threshold_stays_serial()
  local ran_serial = false
  local result = spec_lane.run({
    profile = "contract",
    workers = 3,
    run_command = function()
      ran_serial = true
      return { ok = true, code = 0, output = _all_pass_tap() }
    end,
    run_lanes = function()
      error("contract must not shard")
    end,
  })
  check.is_true(ran_serial)
  check.equal(0, result.code)
end

-- LPT 分片路径契约:文件数超过阈值(30)的具名 profile 且 worker > 1 时,每
-- worker 一条 runner 进程(helper/output/pattern 取自 profile config,
-- `--` 后显式文件列表),各 lane 输出按 lane 顺序聚合后统一压缩。依赖真实
-- test/behavior 文件数远超阈值触发分片;run_lanes 注入替身避免真 spawn。
local function
sharded_profile_runs_one_runner_lane_per_worker()
  local captured_lanes
  local result = spec_lane.run({
    profile = "behavior",
    workers = 3,
    run_command = function()
      error("serial path must not run when sharded")
    end,
    run_lanes = function(lanes)
      captured_lanes = lanes
      local results = {}
      for i, lane in ipairs(lanes) do
        results[i] = { label = lane.label, ok = true, output = _all_pass_tap(), exit_code = 0 }
      end
      return true, results
    end,
  })

  check.is_true(#captured_lanes >= 2,
    "behavior should shard into >= 2 lanes, got " .. #captured_lanes)
  for _, lane in ipairs(captured_lanes) do
    check.truthy(lane.label:match("^behavior_w%d+$"), "lane label: " .. lane.label)
    local argv = table.concat(lane.cmd, "\n")
    check.truthy(argv:find("test_runner/runner%.lua"))
    check.matches("--helper=test/helper.lua", argv, 1, true)
    check.matches("--output=TAP", argv, 1, true)
    check.matches("--pattern=test_", argv, 1, true)
    check.matches("test/behavior/", argv, 1, true)
    check.matches("--durations-out=", argv, 1, true)
  end
  -- 3 条 lane × 3 条 ok 行 → 聚合压缩摘要
  check.equal(0, result.code)
  check.equal(#captured_lanes * 3, result.passed)
  check.equal(0, result.failed)
  local labels = {}
  for _, lane in ipairs(captured_lanes) do labels[#labels + 1] = lane.label end
  check.equal(tostring(#captured_lanes * 3) .. " passed\n"
    .. "[spec-lane] COUNTS missing(这些 lane 没有可重算的计数): "
    .. table.concat(labels, ", ") .. "\n", result.stdout)
end

-- 分片失败聚合:任一 lane 输出带 not ok → failed 计数进摘要、exit code 1。
local function
sharded_failure_aggregates_into_failed_summary()
  local result = spec_lane.run({
    profile = "behavior",
    workers = 3,
    run_lanes = function(lanes)
      local results = {}
      for i, lane in ipairs(lanes) do
        if i == 2 then
          results[i] = { label = lane.label, ok = false, exit_code = 1,
            output = "ok 1\nnot ok 2 - failing: shard two broke\n1..2\n" }
        else
          results[i] = { label = lane.label, ok = true, output = _all_pass_tap(), exit_code = 0 }
        end
      end
      return false, results
    end,
  })

  check.equal(1, result.code)
  check.equal(1, result.failed)
  check.equal(7, result.passed)
  check.truthy(result.stdout:find("not ok 2 - failing: shard two broke", 1, true),
    "failure line must survive aggregation: " .. result.stdout)
  check.truthy(result.stdout:find("7 passed, 1 failed", 1, true),
    "summary must count the shard failure: " .. result.stdout)
end

-- #107:时长缓存让每次 lane 分配可能不同;失败时打印 lane → 文件清单(执行
-- 顺序),复现走 --serial 或按清单点跑。
local function
sharded_failure_prints_lane_file_list_in_execution_order()
  local captured_lanes
  local result = spec_lane.run({
    profile = "behavior",
    workers = 3,
    run_lanes = function(lanes)
      captured_lanes = lanes
      local results = {}
      for i, lane in ipairs(lanes) do
        results[i] = { label = lane.label, ok = i ~= 2, exit_code = i == 2 and 1 or 0,
          output = i == 2 and "not ok 1 - broke\n1..1\n" or _all_pass_tap() }
      end
      return false, results
    end,
  })

  check.truthy(result.stdout:find("--serial", 1, true), "repro hint: " .. result.stdout)
  for _, lane in ipairs(captured_lanes) do
    local files = {}
    local after_separator = false
    for _, token in ipairs(lane.cmd) do
      if after_separator then files[#files + 1] = token end
      if token == "--" then after_separator = true end
    end
    local listing = lane.label .. ":\n  " .. table.concat(files, "\n  ") .. "\n"
    check.truthy(result.stdout:find(listing, 1, true), "lane list for " .. lane.label .. ": " .. result.stdout)
  end
end

-- #131:runner 子进程自举 busted 断网时退 3 并打状态词;spec-lane 原样认领为
-- 不可用(退 3、诊断转 stderr),不能压缩成「0 passed」记失败。
local _RUNNER_UNAVAILABLE = "[test_runner] status=unavailable tool=busted step=install\n"
  .. "[test_runner] 详情: luarocks install failed for busted: Warning: Failed searching manifest: "
  .. "Failed downloading https://luarocks.org/manifest-5.4\n"

local function
serial_runner_bootstrap_unavailable_reports_unavailable_not_failed()
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    run_command = function() return { ok = false, code = 3, output = _RUNNER_UNAVAILABLE } end,
  })

  check.equal(3, result.code)
  check.equal("unavailable", result.status)
  check.equal(0, result.passed)
  check.equal(0, result.failed)
  check.equal("", result.stdout)
  check.equal(_RUNNER_UNAVAILABLE, result.stderr)
end

-- 构建错误不是网络问题:照旧退 1,且车道输出要带上原因,不能只剩「0 passed」。
local function
serial_runner_bootstrap_build_error_stays_failed_with_reason()
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    run_command = function()
      return { ok = false, code = 1, output = "test_runner: luarocks install failed for busted: "
        .. "Error: Build error: Failed compiling object src/term/core.obj\n" }
    end,
  })

  check.equal(1, result.code)
  check.is_nil(result.status)
  check.matches("Failed compiling object src/term/core.obj", result.stdout, 1, true)
end

local function
serial_real_spec_failure_stays_failed()
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    run_command = function()
      return { ok = false, code = 1, output = "ok 1 - fine\nnot ok 2 - broke\n1..2\n" }
    end,
  })

  check.equal(1, result.code)
  check.is_nil(result.status)
  check.equal(1, result.passed)
  check.equal(1, result.failed)
end

local function _sharded_run(lane_result)
  return spec_lane.run({
    profile = "behavior",
    workers = 3,
    run_lanes = function(lanes)
      local results = {}
      for i, lane in ipairs(lanes) do
        results[i] = lane_result(i, lane)
        results[i].label = lane.label
      end
      return false, results
    end,
  })
end

local function
sharded_all_lanes_unavailable_reports_unavailable_once()
  local result = _sharded_run(function()
    return { ok = false, exit_code = 3, output = _RUNNER_UNAVAILABLE }
  end)

  check.equal(3, result.code)
  check.equal("unavailable", result.status)
  check.equal(0, result.failed)
  check.equal("", result.stdout)
  check.equal(_RUNNER_UNAVAILABLE, result.stderr)
end

local function
sharded_unavailable_with_real_failure_stays_failed()
  local result = _sharded_run(function(i)
    if i == 1 then return { ok = false, exit_code = 3, output = _RUNNER_UNAVAILABLE } end
    return { ok = false, exit_code = 1, output = "not ok 1 - broke\n1..1\n" }
  end)

  check.equal(1, result.code)
  check.is_nil(result.status)
  check.matches("not ok 1 - broke", result.stdout, 1, true)
end

-- #130:两条入口曾经各报一个数——分片路径数 TAP 的 ok 行,串行/verify 打印
-- runner 进程内的 COUNTS。stdout/stderr 合流会把 ok 行从中间切开,ok 行口径
-- 因此会漏计;COUNTS 才是权威。这里用「被切开的 ok 行」钉住:分片摘要取
-- COUNTS 合计、补上聚合 COUNTS 行、并对不一致点名。
local function
sharded_summary_uses_counts_when_tap_lines_are_corrupted()
  local captured
  local result = spec_lane.run({
    profile = "behavior",
    workers = 3,
    run_lanes = function(lanes)
      captured = lanes
      local results = {}
      for i, lane in ipairs(lanes) do
        -- 第一条 lane 丢了一条 ok 行(变成 k 2),COUNTS 仍记录真实通过数。
        results[i] = { label = lane.label, ok = true, exit_code = 0,
          output = "ok 1 - a\nk 2 - b\n1..2\n# COUNTS: files=2 cases=2 passed=2 failed=0 errors=0\n" }
      end
      return true, results
    end,
  })

  check.equal(0, result.code)
  check.equal(#captured * 2, result.passed)
  check.equal(0, result.failed)
  check.matches("COUNT MISMATCH", result.stdout, 1, true)
  check.matches("# COUNTS: files=" .. #captured * 2
    .. " cases=" .. #captured * 2 .. " passed=" .. #captured * 2
    .. " failed=0 errors=0", result.stdout, 1, true)
  check.matches(tostring(#captured * 2) .. " passed", result.stdout, 1, true)
end

-- 串行路径同样以 COUNTS 为准:只丢 ok 行、退出码仍为 0 时不得少报通过数。
local function
serial_summary_uses_counts_when_tap_lines_are_corrupted()
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    run_command = function()
      return { ok = true, code = 0,
        output = "ok 1 - a\nk 2 - b\n1..2\n# COUNTS: files=1 cases=2 passed=2 failed=0 errors=0\n" }
    end,
  })
  check.equal(0, result.code)
  check.equal(2, result.passed)
  check.matches("2 passed", result.stdout, 1, true)
  check.matches("COUNT MISMATCH", result.stdout, 1, true)
  check.matches("# COUNTS: files=1 cases=2 passed=2 failed=0 errors=0", result.stdout, 1, true)
end

-- COUNTS 里的失败必须变成真实失败,即便对应 not ok 行已被串流吃掉。
local function
counts_failures_fail_the_lane_even_without_not_ok_lines()
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    run_command = function()
      return { ok = true, code = 0,
        output = "ok 1 - a\n1..2\n# COUNTS: files=1 cases=2 passed=1 failed=1 errors=0\n" }
    end,
  })
  check.equal(1, result.code)
  check.equal(1, result.passed)
  check.equal(1, result.failed)
end

-- 失败判定同样取并集:COUNTS 全绿但 TAP 有 not ok、子进程还退 0 时,
-- 不得因为相信 COUNTS 就把失败行滤掉并假绿。
local function
tap_failure_with_all_green_counts_still_fails()
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    run_command = function()
      return { ok = true, code = 0,
        output = "ok 1 - a\nnot ok 2 - b\n1..2\n# COUNTS: files=1 cases=2 passed=2 failed=0 errors=0\n" }
    end,
  })
  check.equal(1, result.code)
  check.equal(2, result.passed)
  check.equal(1, result.failed)
  check.matches("not ok 2 - b", result.stdout, 1, true)
  check.matches("2 passed, 1 failed", result.stdout, 1, true)
  check.matches("COUNT MISMATCH", result.stdout, 1, true)
end

-- verbose 保留原文,也不能因此丢掉计数交叉核对的告警。
local function
verbose_still_reports_count_mismatch()
  local raw = "ok 1 - a\nk 2 - b\n1..2\n# COUNTS: files=1 cases=2 passed=2 failed=0 errors=0\n"
  local result = spec_lane.run({
    profile = "contract",
    workers = 1,
    verbose = true,
    run_command = function() return { ok = true, code = 0, output = raw } end,
  })
  check.equal(0, result.code)
  check.matches("k 2 - b", result.stdout, 1, true)
  check.matches("COUNT MISMATCH", result.stdout, 1, true)
end

-- #131 + #130:混有真实失败时不可用 lane 仍然只退出失败优先级,不进入
-- COUNTS 合计;总账只覆盖真正执行过的 lane,不因不可用输出缺 COUNTS 而退回 TAP。
local function
sharded_real_failure_excludes_unavailable_lane_from_counts()
  local captured
  local result = spec_lane.run({
    profile = "behavior",
    workers = 3,
    run_lanes = function(lanes)
      captured = lanes
      local results = {}
      for i, lane in ipairs(lanes) do
        if i == 1 then
          results[i] = { label = lane.label, ok = false, exit_code = 3, output = _RUNNER_UNAVAILABLE }
        elseif i == 2 then
          results[i] = { label = lane.label, ok = false, exit_code = 1,
            output = "1..1\n# COUNTS: files=1 cases=1 passed=0 failed=1 errors=0\n" }
        else
          results[i] = { label = lane.label, ok = true, exit_code = 0,
            output = "ok 1 - a\n1..1\n# COUNTS: files=1 cases=1 passed=1 failed=0 errors=0\n" }
        end
      end
      return false, results
    end,
  })
  check.equal(1, result.code)
  check.is_nil(result.status)
  check.equal(#captured - 2, result.passed)
  check.equal(1, result.failed)
  check.matches("# COUNTS: files=" .. #captured - 1
    .. " cases=" .. #captured - 1 .. " passed=" .. #captured - 2
    .. " failed=1 errors=0", result.stdout, 1, true)
end

local function
parse_args_reads_evidence_dir_and_recount()
  local opts = spec_lane.parse_args({ "--profile", "tooling", "--evidence-dir=tmp/evidence" })
  check.equal("tmp/evidence", opts.evidence_dir)
  local recount = spec_lane.parse_args({ "--recount", "tmp/evidence" })
  check.equal("tmp/evidence", recount.recount)
  local missing, err = spec_lane.parse_args({ "--recount" })
  check.is_nil(missing)
  check.matches("missing --recount", tostring(err), 1, true)
end

-- 证据落盘走的是真实文件系统:跑完后仅凭目录就能重算出同一个汇总值。
local function
run_writes_recomputable_evidence()
  local dir = require("foundation.env").make_temp_path("spec_lane_evidence_spec", "")
  require("foundation.fs").remove_path(dir)
  local ok, err = xpcall(function()
    local lane_count
    local result = spec_lane.run({
      profile = "behavior",
      workers = 3,
      evidence_dir = dir,
      run_lanes = function(lanes)
        lane_count = #lanes
        local results = {}
        for i, lane in ipairs(lanes) do
          results[i] = { label = lane.label, ok = true, exit_code = 0,
            output = _all_pass_tap() .. "# COUNTS: files=1 cases=3 passed=3 failed=0 errors=0\n" }
        end
        return true, results
      end,
    })
    check.equal(0, result.code)
    local recount = spec_lane.recount(dir)
    check.equal(0, recount.code, recount.stdout)
    check.matches("status=match", recount.stdout, 1, true)
    check.matches("cases=" .. lane_count * 3, recount.stdout, 1, true)
  end, debug.traceback)
  require("foundation.fs").remove_path(dir)
  if not ok then error(err) end
end

local function
recount_reports_a_mismatch_as_a_real_failure()
  local result = spec_lane.recount("tmp/does-not-exist-evidence")
  check.equal(1, result.code)
  check.matches("status=mismatch", result.stdout, 1, true)
end

-- 缺 COUNTS 时 nil == nil 也不能算 match:没有原始计数就无从重算,退 1。
local function
recount_missing_counts_is_a_real_failure()
  local dir = require("foundation.env").make_temp_path("spec_lane_recount_missing_counts", "")
  require("foundation.fs").remove_path(dir)
  local ok, err = xpcall(function()
    check.is_true(spec_evidence.write(dir, {
      profile = "contract", mode = "serial", exit_code = 0,
      lanes = { { label = "contract", raw = "ok 1 - a\n1..1\n" } },
    }))
    local result = spec_lane.recount(dir)
    check.equal(1, result.code)
    check.matches("status=mismatch", result.stdout, 1, true)
    check.matches("missing COUNTS", result.stdout, 1, true)
  end, debug.traceback)
  require("foundation.fs").remove_path(dir)
  if not ok then error(err) end
end

-- #298 的发现式包结构：tooling 车道 33 行手维护 ROOT 清单
-- 废除,塌缩为 tools/**/test/ + test/support/**/test/ 双口径自动收养。
local function
discover_test_roots_covers_both_scopes()
  local roots, err = lane_tools.discover_test_roots()
  check.is_not_nil(roots, tostring(err))
  check.equal(nil, err)
  check.is_true(#roots > 0, "discovery must find at least one test root")
end

local function
discover_test_roots_returns_sorted_unique_test_dirs()
  local roots = lane_tools.discover_test_roots()
  local seen = {}
  local previous = ""
  for _, root in ipairs(roots) do
    check.truthy(root:find("/test$"), "root must be a test dir: " .. root)
    check.is_nil(seen[root], "duplicate root: " .. root)
    seen[root] = true
    check.truthy(previous <= root, "roots must be sorted: " .. previous .. " > " .. root)
    previous = root
  end
end

-- 双口径同时匹配新旧布局:同名对时代(foo.lua + foo/test/)与目录即包时代
-- (<pkg>/test/)的测试目录都要被收养。
local function
discover_test_roots_adopts_both_layout_shapes()
  local roots = lane_tools.discover_test_roots()
  local index = {}
  for _, root in ipairs(roots) do
    index[root] = true
  end
  -- 目录即包时代:tools/packages/spec_lane.lua + 同包 test/
  check.is_true(index["tools/packages/spec_lane/test"],
    "package-as-dir root must be adopted")
  -- 同名对时代:test/support/behavior_parallel.lua + behavior_parallel/test/
  check.is_true(index["test/support/behavior_parallel/test"],
    "support same-name-pair root must be adopted")
  -- 目录即包时代:test/support/runner_infra/ 无同名 .lua,纯 <pkg>/test/ 形态
  check.is_true(index["test/support/runner_infra/test"],
    "package-as-dir root must be adopted")
end


describe("spec lane public contracts", function()
  it("parse_args_requires_profile", parse_args_requires_profile)
  it("parse_args_parses_profile", parse_args_parses_profile)
  it("parse_args_defaults_to_sharding_eligible", parse_args_defaults_to_sharding_eligible)
  it("parse_args_parses_verbose_alongside_profile", parse_args_parses_verbose_alongside_profile)
  it("parse_args_rejects_removed_busted_bin_escape_hatch", parse_args_rejects_removed_busted_bin_escape_hatch)
  it("compress_tap_collapses_all_pass_tap_to_single_passed_line", compress_tap_collapses_all_pass_tap_to_single_passed_line)
  it("run_defaults_to_explicit_real_busted_runner", run_defaults_to_explicit_real_busted_runner)
  it("runner_spawn_carries_tool_discovery_env", runner_spawn_carries_tool_discovery_env)
  it("small_profile_below_threshold_stays_serial", small_profile_below_threshold_stays_serial)
  it("sharded_profile_runs_one_runner_lane_per_worker", sharded_profile_runs_one_runner_lane_per_worker)
  it("sharded_failure_aggregates_into_failed_summary", sharded_failure_aggregates_into_failed_summary)
  it("sharded_failure_prints_lane_file_list_in_execution_order",
    sharded_failure_prints_lane_file_list_in_execution_order)
  it("serial_runner_bootstrap_unavailable_reports_unavailable_not_failed",
    serial_runner_bootstrap_unavailable_reports_unavailable_not_failed)
  it("serial_runner_bootstrap_build_error_stays_failed_with_reason",
    serial_runner_bootstrap_build_error_stays_failed_with_reason)
  it("serial_real_spec_failure_stays_failed", serial_real_spec_failure_stays_failed)
  it("sharded_all_lanes_unavailable_reports_unavailable_once", sharded_all_lanes_unavailable_reports_unavailable_once)
  it("sharded_unavailable_with_real_failure_stays_failed", sharded_unavailable_with_real_failure_stays_failed)
  it("sharded_summary_uses_counts_when_tap_lines_are_corrupted",
    sharded_summary_uses_counts_when_tap_lines_are_corrupted)
  it("serial_summary_uses_counts_when_tap_lines_are_corrupted",
    serial_summary_uses_counts_when_tap_lines_are_corrupted)
  it("counts_failures_fail_the_lane_even_without_not_ok_lines",
    counts_failures_fail_the_lane_even_without_not_ok_lines)
  it("tap_failure_with_all_green_counts_still_fails", tap_failure_with_all_green_counts_still_fails)
  it("verbose_still_reports_count_mismatch", verbose_still_reports_count_mismatch)
  it("sharded_real_failure_excludes_unavailable_lane_from_counts",
    sharded_real_failure_excludes_unavailable_lane_from_counts)
  it("parse_args_reads_evidence_dir_and_recount", parse_args_reads_evidence_dir_and_recount)
  it("run_writes_recomputable_evidence", run_writes_recomputable_evidence)
  it("recount_reports_a_mismatch_as_a_real_failure", recount_reports_a_mismatch_as_a_real_failure)
  it("recount_missing_counts_is_a_real_failure", recount_missing_counts_is_a_real_failure)
  it("discover_test_roots_covers_both_scopes", discover_test_roots_covers_both_scopes)
  it("discover_test_roots_returns_sorted_unique_test_dirs", discover_test_roots_returns_sorted_unique_test_dirs)
  it("discover_test_roots_adopts_both_layout_shapes", discover_test_roots_adopts_both_layout_shapes)
end)
