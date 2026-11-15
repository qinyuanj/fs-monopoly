-- verify 的车道表:default(七层 + foundation 全跑,tooling 按需挂载)。
-- 选哪张由 lanes.resolve 决定,这里只负责造表。
local shell_lib = require("foundation.shell")

local builders = {}

-- spec-lane 车道默认后端 = 真实 busted 运行器
-- (packages.test_runner.lua54.argv_prefix)。--busted-bin / BUSTED_BIN
-- 逃生舱已删,verify_full 不注入任何覆写。
-- #237 / ADR 0083:并行车道退场,verify 只剩串行一种形态,所以 spec-lane 车道一律带
-- --serial(分片并行不再发生在 verify 里)。车道命令本身的口径(脚本路径、profile 名)
-- 原样保留,不在本工单里改。
local function _spec_lane_cmd(profile, evidence_dir, lua54_bin)
  local argv = {
    lua54_bin or "lua",
    "tools/packages/spec_lane/spec_lane.lua",
    "--profile",
    profile,
    "--serial",
  }
  -- #130:证据目录透传给 spec-lane,原始 TAP 与 COUNTS 逐 lane 落盘,事后可
  -- `spec-lane --recount <dir>/<profile>` 仅凭目录重算。
  if evidence_dir ~= nil then
    argv[#argv + 1] = "--evidence-dir=" .. evidence_dir .. "/" .. profile
  end
  return shell_lib.build_command(argv)
end

-- lint 用钉定 Lua 5.4 从受控 tree 装载 luacheck;缺依赖或版本越界由 runner 报失败。
-- 此处仅在未解析到 Lua 5.4 时登记跳过;正常 verify 在构造车道前已校验解释器。
-- #449: lint 按目录拆三条子车道(lint-src / lint-test / lint-tools),每条独立报
-- PASS/FAIL、可按 lane 名下钻;#237 起 verify 逐车道串行,三条按序执行。
local LINT_TARGETS = { "src", "test", "tools" }

local function _add_lint_or_skip(lanes, skipped, env)
  if env.lua54_bin then
    for _, target in ipairs(LINT_TARGETS) do
      lanes[#lanes + 1] = {
        label = "lint-" .. target,
        cmd = shell_lib.build_command({ env.lua54_bin, "tools/packages/lint/runner.lua", target }),
      }
    end
  else
    for _, target in ipairs(LINT_TARGETS) do
      skipped[#skipped + 1] = "lint-" .. target
    end
  end
end

-- 层边界门禁住在 guards 车道(arch_policy_guard 执行 policy.json);旧外部
-- 架构工具的独立 arch 车道随 #94 退场。CRAP / 变异不进 verify,走 DSH 插件的
-- uml_crap / uml_mutate(ADR 0082)。
-- #237:serial 参数随并行退场一起删掉——它已恒真(verify 只有串行),留着只会误导。
function builders.default(env, include_tooling, evidence_dir)
  local lanes, skipped = {}, {}
  lanes[#lanes + 1] = { label = "contract", cmd = _spec_lane_cmd("contract", evidence_dir, env.lua54_bin) }
  lanes[#lanes + 1] = { label = "guards", cmd = _spec_lane_cmd("guards", evidence_dir, env.lua54_bin) }
  lanes[#lanes + 1] = { label = "behavior", cmd = _spec_lane_cmd("behavior", evidence_dir, env.lua54_bin) }
  -- #237 / #234 F5:slim 车道按验收原文包含 foundation(七层之外的工具底座),
  -- 不再只挂在 --tooling 下。profile 走目录点跑(tools/foundation 下的 test/**)。
  lanes[#lanes + 1] = { label = "foundation", cmd = _spec_lane_cmd("tools/foundation", evidence_dir, env.lua54_bin) }
  _add_lint_or_skip(lanes, skipped, env)
  lanes[#lanes + 1] = { label = "encoding",
    cmd = shell_lib.build_command({ env.lua54_bin or "lua", "tools/packages/encoding/encoding.lua", "check" }) }
  -- property 车道已退场(测试极简化决策/monopoly#190):道具时机 fuzz 探针分片并入
  -- behavior 车道,默认 verify 就跑得到,不再需要独立入口。
  if include_tooling then
    lanes[#lanes + 1] = { label = "tooling", cmd = _spec_lane_cmd("tooling", evidence_dir, env.lua54_bin) }
  end
  return lanes, skipped
end

return builders
