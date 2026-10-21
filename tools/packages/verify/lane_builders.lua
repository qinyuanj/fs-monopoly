-- verify 的车道表:default(七层 + foundation 全跑,tooling 按需挂载)。
-- 选哪张由 lanes.resolve 决定,这里只负责造表。
local shell_lib = require("foundation.shell")

local builders = {}

-- spec-lane 车道默认后端 = 真实 busted 运行器
-- (packages.test_runner.lua54.argv_prefix)。--busted-bin / BUSTED_BIN
-- 逃生舱已删,verify_full 不注入任何覆写。
local function _spec_lane_cmd(profile, evidence_dir, lua54_bin)
  local argv = {
    lua54_bin or "lua5.4",
    "tools/packages/spec_lane/spec_lane.lua",
    "--profile",
    profile,
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
-- #449: lint 按目录拆三条并行子车道(lint-src / lint-test / lint-tools),
-- 每条独立报 PASS/FAIL、可按 lane 名下钻;即便 luacheck 单进程回退
-- (LuaLanes 缺失),车道级并行也能把 wall 压进 slim 预算。
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
-- 架构工具的独立 arch 车道随 #94 退场。CRAP / 变异不进 verify,走显式
-- `lua5.4 tools/cli.lua uml crap|mutate`。
function builders.default(env, include_tooling, serial, evidence_dir)
  local lanes, skipped = {}, {}
  lanes[#lanes + 1] = { label = "contract", cmd = _spec_lane_cmd("contract", evidence_dir, env.lua54_bin) }
  lanes[#lanes + 1] = { label = "guards", cmd = _spec_lane_cmd("guards", evidence_dir, env.lua54_bin) }
  local lua = env.lua54_bin or "lua5.4"
  lanes[#lanes + 1] = { label = "behavior",
    cmd = shell_lib.build_command({ lua, "test/support/behavior_parallel.lua" }) }
  _add_lint_or_skip(lanes, skipped, env)
  lanes[#lanes + 1] = { label = "encoding",
    cmd = shell_lib.build_command({ lua, "tools/packages/encoding/encoding.lua", "check" }) }
  -- property 车道已退场(测试极简化决策/monopoly#190):道具时机 fuzz 探针分片并入
  -- behavior 车道并行吸收,默认 verify 就跑得到,不再需要独立入口。
  if include_tooling then
    lanes[#lanes + 1] = {
      label = "tooling",
      cmd = shell_lib.build_command({ lua, "test/support/behavior_parallel.lua", "--profile", "tooling" }),
    }
  end
  if serial then
    for _, lane in ipairs(lanes) do
      if lane.label == "behavior" or lane.label == "tooling" or lane.label == "contract" or lane.label == "guards" then
        local argv = { env.lua54_bin, "tools/packages/spec_lane/spec_lane.lua", "--profile", lane.label, "--serial" }
        if evidence_dir ~= nil then
          argv[#argv + 1] = "--evidence-dir=" .. evidence_dir .. "/" .. lane.label
        end
        lane.cmd = shell_lib.build_command(argv)
      end
    end
  end
  return lanes, skipped
end

return builders
