-- packages/ops/cli.lua —— deploy 子命令(部署件挂载进封闭命令集)
--
-- 统一接口形态(#300 决议):本文件 return 纯接口模块:
--   M.main(args, env) -> 退出码(0 成功 / 1 业务失败 / 2 用法错误)
--   M.usage()         -> 完整 usage 文本(包内单一真源,顶层 <cmd> --help 转发)
--
-- 实现:子进程转发 tools/packages/ops/deploy.lua,退出码透传。deploy.lua 直跑时
-- 经 script_bootstrap 自举 package.path,原语取 foundation(#222);在原生 Windows 上
-- 运行、写入 Windows 侧 Eggy 宿主目录(ADR 0083)。
-- --help/-h 在壳内消费返回 usage;其余参数原样透传,deploy.lua 自身零参数接口
-- 报错语义不变(任何参数 → ERROR + exit 1,#384 继承的 deploy.ps1 空 param())。
local M = {}

local tool_cli = require("foundation.tool_cli")

local DEPLOY_ENTRY = "tools/packages/ops/deploy.lua"

function M.usage()
  return table.concat({
    "用法: lua tools/cli.lua deploy",
    "",
    "把 src/ + main.lua + Data/ 按原样部署到 Windows 侧 Eggy 宿主目录(LuaSource_大富翁)。",
    "拷贝的是工作树而非 HEAD:payload 里有未提交文件时列出(WARNING,仅提示,不影响退出码)。",
    "零参数、零开关;任何多余参数 → ERROR + exit 1(deploy.lua 自身 CLI 面不变)。",
    "在原生 Windows 上运行(ADR 0083):家目录直接取 %USERPROFILE%,目录镜像走原生 robocopy;",
    "不经互操作层取家目录、不做挂载点路径换算,也不依赖 bash 的选择。",
    "退出码: 0 成功 / 1 部署失败(拷贝或读写出错;多余参数按历史口径也退 1) /",
    "退 3 不可用:缺 robocopy 或取不到 %USERPROFILE%(status=unavailable,未改动部署目录;",
    "这是环境问题,不是部署失败)。本子命令不用 2。",
    "目标路径: <家目录>/Desktop/dev/eggy/LuaSource_大富翁;家目录即 %USERPROFILE%,",
    "设了 MONOPOLY_DEPLOY_HOME 时以它为准(测试与沙箱用)。",
    "要看实际路径或比对部署目录,跑只读的 `lua tools/cli.lua deploy-diff`,不要全盘 find。",
    "行为真源见 tools/packages/ops/deploy.lua。",
    "",
  }, "\n") .. "\n"
end

function M.main(args, env)
  local help = tool_cli.help_exit(args, M.usage)
  if help ~= nil then
    return help
  end
  -- 转发走 foundation 的统一执行缝:argv 原样交给子进程,不再自己拼 os.execute 命令串
  -- (原生 Windows 的 os.execute 走 cmd.exe,POSIX 引号与中文参数都过不去)。
  return tool_cli.forward_subprocess(DEPLOY_ENTRY, args)
end

return M
