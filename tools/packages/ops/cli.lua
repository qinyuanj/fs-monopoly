-- packages/ops/cli.lua —— deploy 子命令(部署件挂载进封闭命令集)
--
-- 统一接口形态(#300 决议):本文件 return 纯接口模块:
--   M.main(args, env) -> 退出码(0 成功 / 1 业务失败 / 2 用法错误)
--   M.usage()         -> 完整 usage 文本(包内单一真源,顶层 <cmd> --help 转发)
--
-- 实现:子进程转发 tools/packages/ops/deploy.lua,退出码透传。deploy.lua 自包含
-- 决策(只用 Lua 5.4 标准库,不 require foundation.*;唯一例外是不可用时 dofile
-- platform_boundary 渲染退 3 诊断),在 WSL 中运行、写入
-- Windows 侧 Eggy 宿主目录(ADR 0073)。
-- --help/-h 在壳内消费返回 usage;其余参数原样透传,deploy.lua 自身零参数接口
-- 报错语义不变(任何参数 → ERROR + exit 1,#384 继承的 deploy.ps1 空 param())。
local M = {}

local DEPLOY_ENTRY = "tools/packages/ops/deploy.lua"

local function _shell_quote(value)
  local text = tostring(value or "")
  assert(not text:find("[\r\n%z]"), "Unsupported command argument")
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua deploy",
    "",
    "把 src/ + main.lua + Data/ 按原样部署到 Windows 侧 Eggy 宿主目录(LuaSource_大富翁)。",
    "拷贝的是工作树而非 HEAD:payload 里有未提交文件时列出(WARNING,仅提示,不影响退出码)。",
    "零参数、零开关;任何多余参数 → ERROR + exit 1(deploy.lua 自身 CLI 面不变)。",
    "在 WSL Ubuntu 中运行(ADR 0073):目标经 cmd.exe 取 %USERPROFILE% 再按 wslpath 换算;",
    "没有 cmd.exe / wslpath 时退 3(status=unavailable,环境问题不是部署失败)。",
    "行为真源见 tools/packages/ops/deploy.lua。",
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
  local parts = { require("foundation.lua54").lua54_bin(), DEPLOY_ENTRY }
  for _, value in ipairs(args or {}) do
    parts[#parts + 1] = _shell_quote(value)
  end
  local ok, how, code = os.execute(table.concat(parts, " "))
  if how == "exit" then
    return code or (ok and 0 or 1)
  end
  return 1
end

return M
