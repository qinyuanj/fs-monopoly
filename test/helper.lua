--- Shared test helper loaded via spec_profiles helper entry; sets package.path
--- and installs Eggy fakes.
--- Specs that need per-test runtime refresh opt in explicitly.
---
--- 覆盖率不在本仓运行器内采集(插件 uml_crap 由 crapper 自带 luacov 路径，#94)，
--- helper 仅负责运行时与用例生命周期。

require("test.bootstrap")

local options = ...
local events = assert(options and options.busted, "real busted lifecycle required")
local env_runtime = require("test.env_runtime")
env_runtime.refresh()

local test_env = require("test.support.env")
local runtime_baseline_guard = require("test.support.runtime_baseline_guard")

-- 套件级 RNG 重播:behavior 套共用单条全局 math.random 序列,各 spec 消耗的抽数不定
-- (掷骰、抽卡、AI 决策……),会让进入后续用例的 RNG 状态取决于「同进程/同 worker 里
-- 此前跑了什么、抽了多少」。任何断言依赖「进入时 RNG 状态」的用例都可能在并行 LPT
-- 分桶重排后假红。本 helper 订阅已验证真实 busted 的项目生命周期，
-- 每例完整 before_each 链开始前统一重播
-- test_env.DEFAULT_SEED,从源头消除泄漏,取代逐 spec 的 randomseed(1) band-aid
-- (#45/#46)。守卫见 test/behavior/foundation/test_rng_reset_isolation.lua。
--
-- 仅限 behavior 套:contract/guards/property/tooling 不依赖 RNG。按 it() 调用点
-- 的 trace.source 判定 —— 它指向 spec 文件本身(对 `it(case.name, case.run)` 的场景
-- 套件亦然),且未被 short_src 的定长截断吃掉「test/behavior」前缀。
local function _is_behavior_spec(element)
  local trace = element and element.trace
  local source = trace and trace.source
  if type(source) ~= "string" then
    return false
  end
  return source:gsub("\\", "/"):find("test/behavior", 1, true) ~= nil
end

events.subscribe({ "project", "case", "start" }, function(element)
  if _is_behavior_spec(element) then
    test_env.reseed_defaults()
  end
  return nil, true
end)

-- 共享运行时端口基线守卫(#217):test end 事件在所有 after_each 之后触发,此刻
-- runtime ports / 付费网关 / 分享面板 port 应仍处于共享基线的已配置态。谁的
-- teardown 拆到未配置态
-- 不装回,当场记为泄漏——先装回基线止住同进程扩散,再落 `# BASELINE LEAK` 行点名
-- (behavior_parallel 按此行聚合失败明细),收尾把计数打进 errors 让车道硬失败,
-- 不再靠 suite 顺序侥幸掩盖(mutate 车道的窄 suite 子集就是这么翻车的)。
local baseline_leak_count = 0
events.subscribe({ "project", "case", "end" }, function(element)
  if not _is_behavior_spec(element) then
    return nil, true
  end
  local missing = runtime_baseline_guard.check_and_restore()
  if #missing > 0 then
    baseline_leak_count = baseline_leak_count + 1
    local source = tostring(element.trace and element.trace.source or "?"):gsub("^@", "")
    io.write("# BASELINE LEAK: " .. source .. " :: " .. tostring(element.full_name or element.name)
      .. " 拆了共享端口基线未装回: " .. table.concat(missing, ", ")
      .. "(teardown 调 shared_support.restore_runtime_services() 装回,#217)\n")
  end
  return nil, true
end)
events.subscribe({ "project", "suite", "end" }, function()
  if baseline_leak_count > 0 then
    options.counts.errors = options.counts.errors + baseline_leak_count
  end
  return nil, true
end)

return env_runtime
