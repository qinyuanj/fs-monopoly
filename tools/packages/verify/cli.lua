-- packages/verify/cli.lua —— verify 子命令(wayfinder #307 包内实现)
--
-- 统一接口形态(#300 决议):本文件 return 纯接口模块:
--   M.main(args, env) -> 退出码(0 成功 / 1 业务失败 / 2 用法错误 / 3 有车道不可用且无真实失败,#112)
--   M.usage()         -> 完整 usage 文本(包内单一真源,顶层 <cmd> --help 转发)
--
-- 实现:子进程转发包内编排入口 main.lua(原 tools/quality/verify_full.lua,
-- #307 包迁后入口随包),flag 解析与 os.exit 语义原样住入口,退出码透传。
local M = {}

local ENTRY = "tools/packages/verify/main.lua"

-- 原生 argv 转发，与 foundation 的 cmd quoting 保持单一真源。
-- #124:工具发现(解释器全路径 + luarocks.exe)在这里解析一次,经 options.env
-- 导出给编排子进程;车道与测试子进程树继承后不再各自重复 where 探测。
local function _forward(args)
  require("test.bootstrap").install_package_paths()
  local proc = require("foundation.proc")
  local lua54 = require("foundation.lua54")
  local command = { lua54.lua54_bin(), ENTRY }
  for _, value in ipairs(args or {}) do
    command[#command + 1] = value
  end
  local discovery = require("foundation.bootstrap").tool_discovery_env()
  local result = proc.run_command(command, discovery ~= nil and { env = discovery } or nil)
  io.write(result.output or "")
  return result.code or (result.ok and 0 or 1)
end

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua verify [--serial|--parallel|--tooling|--verbose] [--evidence-dir=<目录>]",
    "",
    "质量门禁编排器:默认 slim 车道(contract + guards(含 arch_policy 层边界门禁)",
    "+ behavior 七层 + foundation + lint-src/lint-test/lint-tools + encoding),",
    "是迭代默认与 push 前唯一硬地板。",
    "",
    "flag 映射:",
    "  --serial       所有车道及其测试子进程按序执行(当前默认)",
    "  --parallel     POSIX 后台并行(set -m 进程组 + 看门狗超时收容整组);",
    "                 空输出按失败计",
    "  (默认)         slim:七层 + foundation 行为 spec 全跑",
    "  --tooling      正交叠加 tooling 并行 lane(改 tools/** 时)",
    "  --verbose      展开各 lane 明细",
    "  --evidence-dir 测量证据落盘(#130):spec-lane 车道把原始 TAP/COUNTS 写到 <目录>/<lane>",
    "                 (用 `lua5.4 tools/cli.lua spec-lane --recount <目录>/<lane>` 重算核对),",
    "                 verify 另存每条 lane 完整输出 <lane>.out 与整体报告 summary.txt",
    "",
    "挑选提示:",
    "  - CRAP / 变异测试不进 verify,是显式 uml 质量步骤:",
    "    `lua5.4 tools/cli.lua uml crap` / `lua5.4 tools/cli.lua uml mutate`(ADR 0068)。",
    "  - property 独立车道已退场(#190):两个道具时机 fuzz 探针",
    "    (test/behavior/rules/items/test_item_timing_fuzz.lua、",
    "    test/behavior/turn/test_item_timing_loop_fuzz.lua)随默认 verify 跑",
    "    (400 seeds;MONOPOLY_FUZZ_SEEDS 可放大做 soak,FUZZ_ONLY_SEED=<n> 单 seed 复放)。",
    "  - 红车道 → 看 `[verify] FAIL <lane>` 行,按 lane 名下钻",
    "    (spec-lane --profile <目录> 或单文件)。",
    "",
    "pipeline 不包含(按需走单工具):uml crap / uml mutate / dry;",
    "dry 是软车道,由邻接 .uml-viewer/dryer 的 POSIX venv 承接;tooling 中相关探针实际执行。",
    "真源:tools/packages/verify/(main.lua / lane_builders.lua / lanes.lua)。",
    "",
  }, "\n") .. "\n"
end

function M.main(args, env)
  for _, value in ipairs(args or {}) do
    if value == "--help" or value == "-h" then
      io.write(M.usage())
      return 0
    end
  end
  return _forward(args)
end

return M
