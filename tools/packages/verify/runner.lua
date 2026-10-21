-- verify 车道的执行与输出聚合。
-- _build_output 是纯函数(results -> stdout/exit_code),verify_full_spec 直接拿它断言。
local number_utils = require("src.foundation.number")
local parallel_lanes = require("foundation.parallel_lanes")
local availability = require("foundation.tool_availability")

local runner = {}

runner.PHASE_TIMEOUT = 600

-- 串行跑一步。输出回收、stdout/stderr 合流、退出码归一都由 foundation.proc 负责
-- (不在这里手拼 `> file 2>&1` 重定向);
-- 这里只把 ok/code 两路折成 verify 的 success 判据。
function runner.run_step(label, cmd, opts)
  local started = os.time()
  local result = require("foundation.proc").run_command(cmd, opts ~= nil and { env = opts.env } or nil)
  local ok, code = result.ok, result.code
  local elapsed = math.max(0, os.time() - started)
  local success = ok == true and (code == nil or code == 0)
  if not success and number_utils.is_numeric(code) then
    success = code == 0
  end
  return { label = label, ok = success, exit_code = code, elapsed = elapsed, output = result.output or "" }
end

-- 启动 + 调度 + 输出聚合委托给 foundation.parallel_lanes（曾经在这里复制粘贴一份）。
-- stream=false 维持 architect 的"收集后选择性 emit"模型：success 路径压缩、
-- failure/verbose 路径全量打印，由下游 build_output 处理。
function runner.run_parallel(lanes, opts)
  opts = opts or {}
  local started = os.time()
  local all_ok, lane_results = parallel_lanes.run(lanes, {
    stream = false,
    timeout = runner.PHASE_TIMEOUT,
    env = opts.env,
  })
  local elapsed = math.max(0, os.time() - started)

  local results = {}
  for index, lane in ipairs(lane_results) do
    results[index] = {
      label = lane.label,
      ok = lane.ok,
      exit_code = lane.exit_code,
      elapsed = nil,
      output = lane.output or "",
    }
  end
  return all_ok, results, elapsed
end

-- 退 3 的车道是「不可用」(平台或工具不可用):不算通过,
-- 也不混进 failed。三态判定只在这张表里:车道判定与整体判定同源,整体取
-- rank 最高者(有真实失败 1 > 有不可用 3 > 全通过 0);一条车道都没有按失败。
local _STATES = {
  PASS = { rank = 0, exit_code = 0 },
  UNAVAILABLE = { rank = 1, exit_code = availability.EXIT_CODE },
  FAIL = { rank = 2, exit_code = 1 },
}

local function _verdict(r)
  if r.ok then return "PASS" end
  return r.exit_code == availability.EXIT_CODE and "UNAVAILABLE" or "FAIL"
end

-- 成功车道默认压缩成一行;失败、不可用或 verbose 才把车道输出全量摊开。
function runner.build_output(input)
  input = input or {}
  local results = input.results or {}
  local skipped = input.skipped or {}
  local total_elapsed = input.total_elapsed or 0
  local verbose = input.verbose == true

  local buckets = { PASS = {}, FAIL = {}, UNAVAILABLE = {} }
  local overall = #results == 0 and "FAIL" or "PASS"
  for _, r in ipairs(results) do
    local verdict = _verdict(r)
    local bucket = buckets[verdict]
    bucket[#bucket + 1] = r.label
    if _STATES[verdict].rank > _STATES[overall].rank then
      overall = verdict
    end
  end
  local passed, failed, unavailable = buckets.PASS, buckets.FAIL, buckets.UNAVAILABLE
  local exit_code = _STATES[overall].exit_code

  local buf = {}
  for _, r in ipairs(results) do
    local show_this = verbose or not r.ok
    if not show_this then
      local counts = tostring(r.output or ""):match("# COUNTS: [^\r\n]+")
      if counts then buf[#buf + 1] = "[verify] " .. r.label .. " " .. counts .. "\n" end
    end
    if show_this then
      buf[#buf + 1] = string.format(
        "[verify] %s %s  %ds\n",
        _verdict(r), r.label, r.elapsed or 0
      )
      if r.output and r.output ~= "" then
        buf[#buf + 1] = r.output
        if r.output:sub(-1) ~= "\n" then
          buf[#buf + 1] = "\n"
        end
      end
    end
  end

  buf[#buf + 1] = string.format(
    "\n[verify] %s  passed=%d failed=%d%s skipped=%d  %ds\n",
    overall, #passed, #failed,
    #unavailable > 0 and (" unavailable=" .. #unavailable) or "",
    #skipped, total_elapsed
  )
  if #unavailable > 0 then
    buf[#buf + 1] = "[verify] unavailable(未运行,平台或工具不可用;先查环境再重跑):"
      .. table.concat(unavailable, ", ") .. "\n"
  end
  if #skipped > 0 then
    buf[#buf + 1] = "[verify] skipped: " .. table.concat(skipped, ", ") .. "\n"
  end

  return {
    stdout = table.concat(buf),
    exit_code = exit_code,
    passed = passed,
    failed = failed,
    unavailable = unavailable,
    skipped = skipped,
  }
end

return runner
