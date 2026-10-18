-- tooling profile 自动发现（#298）：33 行手维护 ROOT 清单废除，
-- 塌缩为 tools/**/test/ + test/support/**/test/ 自动收养(新旧布局同时匹配)。
-- dofile 而非 require:纯模块无副作用,任何 cwd 从仓根的执行入口(runner /
-- behavior_parallel / spec_lane)都能解析到。
local lane_tools = dofile("tools/packages/spec_lane/spec_lane_tools.lua")
local tooling_roots, tooling_roots_err = lane_tools.discover_test_roots()
if tooling_roots == nil then
  error("tooling 发现式收养失败: " .. tostring(tooling_roots_err))
end

return {
  default = {
    helper = "test/helper.lua",
    output = "test/log_warns_handler.lua",
    pattern = "test_",
  },
  contract = {
    ROOT = {"test/contract"},
    helper = "test/helper.lua",
    output = "TAP",
    pattern = "test_",
  },
  behavior = {
    ROOT = {"test/behavior"},
    helper = "test/helper.lua",
    output = "test/log_warns_handler.lua",
    pattern = "test_",
  },
  -- behavior-smoke profile 已废除；窄反馈改由
  -- `spec-lane --profile <目录>` 按需点跑。
  guards = {
    ROOT = {"test/guards"},
    helper = "test/helper.lua",
    output = "TAP",
    pattern = "test_",
  },
  tooling = {
    ROOT = tooling_roots,
    helper = "test/helper.lua",
    output = "TAP",
    pattern = "test_",
  },
}
