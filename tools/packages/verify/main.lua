-- packages/verify/main.lua —— verify 门禁编排器入口(wayfinder #307 包迁,
-- 原 tools/quality/verify_full.lua)。双重形态:被 require 时返回模块
-- (测试拿 build_output / _resolve_lanes 断言),被 `lua5.4 tools/cli.lua verify`
-- 经包内 cli.lua 子进程 spawn 时解析 flag 并 os.exit。
require("test.bootstrap").install_package_paths()

-- 工具树与 repo_root 在模块加载时解析一次(与其它包入口同口径:
-- `bootstrap.install(<本文件>)` 从源文件路径向上找仓库根,不依赖 cwd)。
require("foundation.bootstrap").install(debug.getinfo(1, "S").source)
local interpreter = require("foundation.lua54")
local lanes_mod = require("packages.verify.lanes")
local runner = require("packages.verify.runner")

-- lua5.4 探测(候选表 + `<candidate> -v` 验证 + 记忆化)原先在这里有一份逐字副本,
-- 与解释器选择真源靠"同口径"的注释手工同步。归一到
-- foundation.lua54.detect_lua54():探不到返回 nil。
local function _resolve_lua54()
  return interpreter.detect_lua54()
end

-- 只为提示:git 不可用时按没有未跟踪文件处理,不走不可用退 3。
local function _untracked_tests()
  local git_query = require("test.guards.lib.git_query")
  return git_query.split_lines(git_query.run_git({ "ls-files", "--others", "--exclude-standard", "test" }))
end

local function _main(opts)
  opts = opts or {}
  local started = os.time()

  local env = { lua54_bin = _resolve_lua54() }
  if env.lua54_bin == nil then error("Lua 5.4 interpreter required; check LUA54_BIN") end

  local plan = lanes_mod.resolve({
    tooling = opts.tooling,
    serial = opts.serial,
    env = env,
    evidence_dir = opts.evidence_dir,
    untracked_tests = _untracked_tests(),
  })

  for _, w in ipairs(plan.warnings) do
    io.write("[verify] warning: " .. w .. "\n")
  end
  io.flush()

  -- #124:工具发现结果随车道命令导出(串行 proc / 并行 command.cmd 同一语义),
  -- 车道及其测试子进程继承 LUA54_BIN / MONOPOLY_LUAROCKS_EXE,不再逐进程探测。
  -- 直跑(非经 cli.lua 转发)时这里自行解析一次;经转发时读到的就是导出值,
  -- 解析只是复核,几乎零成本。
  local spawn_env = require("foundation.bootstrap").tool_discovery_env()

  local parallel_results, parallel_elapsed
  if opts.serial then
    parallel_results = {}
    local lane_started = os.time()
    for _, lane in ipairs(plan.lanes) do
      parallel_results[#parallel_results + 1] = runner.run_step(lane.label, lane.cmd, { env = spawn_env })
    end
    parallel_elapsed = os.time() - lane_started
  else
    local all_ok
    all_ok, parallel_results, parallel_elapsed = runner.run_parallel(plan.lanes, { env = spawn_env })
    if all_ok == nil then error("verify runner returned no result") end
  end
  local all_results = {}
  for _, r in ipairs(parallel_results) do
    r.elapsed = r.elapsed or parallel_elapsed
    all_results[#all_results + 1] = r
  end

  local output = runner.build_output({
    results = all_results,
    skipped = plan.skipped,
    total_elapsed = math.max(0, os.time() - started),
    verbose = opts.verbose == true,
  })

  io.write(output.stdout)
  io.flush()

  -- #130:证据落盘只记录,不改变门禁结论;写失败告警即可。
  if opts.evidence_dir ~= nil then
    local written, evidence_err = require("packages.verify.evidence").write(
      opts.evidence_dir, all_results, output.stdout)
    if not written then
      io.stderr:write("[verify] warning: evidence write failed: " .. tostring(evidence_err) .. "\n")
    end
  end

  return {
    ok = output.exit_code == 0,
    exit_code = output.exit_code,
    passed = output.passed,
    failed = output.failed,
    skipped = plan.skipped,
  }
end

-- argv -> opts。默认并行(#107 已为 spec-lane 恢复并行;#73 的串行默认是 Windows
-- 迁移期安全网):--serial 显式退回串行复现。用法错误返回 nil, 诊断文本。
-- while 而非数值 for:--evidence-dir 的空格形式要多吃一个 argv,数值 for 的循环
-- 变量在循环体内改了也不影响迭代(#130 曾被 luacheck W311 点出这个写法)。
local function _parse_args(argv)
  local opts = { serial = false }
  local i = 1
  while i <= #argv do
    local token = argv[i]
    if token == "--serial" then
      opts.serial = true
    elseif token == "--parallel" then
      opts.serial = false
    elseif token == "--tooling" then
      opts.tooling = true
    elseif token == "--verbose" then
      opts.verbose = true
    elseif token == "--evidence-dir" or token:match("^%-%-evidence%-dir=") then
      local value = token:match("^%-%-evidence%-dir=(.*)$")
      if value == nil then
        value = argv[i + 1]
        i = i + 1
      end
      if value == nil or value == "" then
        return nil, "missing --evidence-dir value"
      end
      opts.evidence_dir = value
    else
      return nil, "unknown flag: " .. tostring(token)
    end
    i = i + 1
  end
  return opts
end

local M = {
  run = _main,
  parse_args = _parse_args,
  build_output = runner.build_output,
  _resolve_lanes = lanes_mod.resolve,
}

if ... == "packages.verify.main" then
  return M
end

local opts, usage_err = _parse_args(arg or {})
if opts == nil then
  io.stderr:write(usage_err .. "\n")
  os.exit(2)
end
local result = _main(opts)
os.exit(result.exit_code)
