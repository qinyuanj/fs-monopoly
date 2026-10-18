-- packages/lint/cli.lua —— lint 子命令(wayfinder #304 骨架 / #320 包退场)
--
-- 统一接口形态(#300 决议):本文件 return 纯接口模块:
--   M.main(args, env) -> 退出码(0 成功 / 1 业务失败 / 2 用法错误 / 3 平台或工具不可用)
--   M.usage()         -> 完整 usage 文本(包内单一真源,顶层 <cmd> --help 转发)
--
-- 实现(#311/#320/#322):薄壳已随包迁落位,进程内调用 packages.lint.runner
-- (不再子进程转发 tools/wrappers/lint.lua);进程内适配收敛在
-- foundation.tool_cli 单点。runner 负责配置校验 + luacheck。
local M = {}

local tool_cli = require("foundation.tool_cli")

local RUN_OPTS = {
  runner_module = "packages.lint.runner",
  runner_script = "tools/packages/lint/runner.lua",
}

function M.usage()
  return table.concat({
    "用法: lua tools/cli.lua lint [path ...]",
    "",
    "luacheck 静态检查:默认扫 src / test / tools(见 .luacheckrc);路径经 args",
    "直通。详细语义见 packages/lint/runner.lua。",
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
  return tool_cli.run(RUN_OPTS, args, env)
end

return M
