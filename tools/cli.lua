-- tools/cli.lua —— 工具链唯一对外面（#300）
--
-- 用法:
--   lua tools/cli.lua <子命令> [args...]
--   lua tools/cli.lua --help | -h
--
-- 调度机制:顶层静态路由表 commands(封闭命令集,子命令集合与「不进」清单
-- 以本文件的封闭命令表为准；伪入口 / swarm / loc 不进）——查表 →
-- require("packages.<pkg>.cli") → cli.main(args, env) → 顶层统一 os.exit。
--
-- 退出码约定(#300 Q2):0 = 成功 / 1 = 业务失败 / 2 = 用法错误(未知子命令、
-- require 失败)/ 3 = 平台或工具不可用(未运行)。缺依赖或版本越界退 1。
-- 包内处理 --help/-h 并返回 0。
--
-- 包内 cli.lua 统一接口形态(#304):
-- return { main = function(args, env) -> 退出码, usage = function() -> string }。
-- 同一包要挂第二个子命令时用可选 module 字段指向包内另一模块(同样的接口形态)。
-- 不在包 cli 里按子命令名分派:deploy-diff 只读,分派失效不能落到会写入的 deploy。
local commands = {
  { name = "verify",            pkg = "verify",             summary = "质量门禁编排器(默认 slim;--tooling 加跑工具链测试)" },
  { name = "spec-lane",         pkg = "spec_lane",          summary = "测试车道运行器(--profile behavior|tooling)" },
  { name = "lint",              pkg = "lint",              summary = "luacheck 静态检查(默认扫 src/test/tools)" },
  { name = "deploy",            pkg = "ops",                summary = "部署到 Windows 侧 Eggy 目录(原生 %USERPROFILE% + robocopy;零参数)" },
  { name = "deploy-diff",       pkg = "ops", module = "deploy_diff", summary = "只读比对部署目录与工作区 payload(有漂移退 1;真机验收后、提交前跑)" },
  { name = "sync-data",         pkg = "data_sync",          summary = "从部署目录回同步导出(Data;EggyAPI/EggyEditorAPI 存根)" },
  { name = "probe",             pkg = "probe",              summary = "试玩态探针(经 editor-cli 在游戏内执行 lua 文件,取回 probe(...) 输出)" },
  { name = "gift-code",         pkg = "gift_code",          summary = "礼包码补偿码生成(new:随机码 → 哈希入码表,明文只打印一次)" },
  { name = "clean",             pkg = "clean",              summary = "清生成物(build/tmp/luacov 等)" },
}

local function _usage()
  local lines = {
    "用法: lua tools/cli.lua <子命令> [args...]",
    "",
    "子命令（封闭命令集）：",
  }
  for _, entry in ipairs(commands) do
    lines[#lines + 1] = string.format("  %-18s %s", entry.name, entry.summary)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "原生 Windows 单平台(ADR 0083);非 Windows 或缺少 bash 判不可用,退 3。"
  lines[#lines + 1] = "退出码:0 成功 / 1 真实失败 / 2 用法错误 / 3 平台或工具不可用(先查环境再重跑)"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "用法提示:"
  lines[#lines + 1] = "  lua tools/cli.lua <子命令> --help   子命令帮助(包内 usage 真源)"
  return table.concat(lines, "\n") .. "\n"
end

-- 入口解释器预检(#191 用户故事 3):入口统一写 `lua`(ADR 0083),具体是哪个
-- 可执行文件由 foundation.lua54 的候选表按 `-v` 校验选出;这里只兜住「有人拿
-- 5.1/5.3 直接跑本文件」——误用别的解释器立即退 1,而不是让旧语义悄悄跑完
-- 一整套测试。
if _VERSION ~= "Lua 5.4" then
  io.stderr:write("Lua 5.4 interpreter required; run `lua tools/cli.lua <子命令>` (found " .. tostring(_VERSION) .. ")\n")
  os.exit(1)
end

-- 引导下沉到 foundation.bootstrap:模块搜索面的口径(含 repo_root/?.lua)只在那边表达。
-- 这里不能 require —— 此刻 package.path 里还没有仓库的任何模式。自制版本只拼了
-- root/tools/?,缺 repo_root/?.lua,只能靠默认的 ./?.lua 兜住,于是只有「cwd = 仓根」
-- 这一格能跑(仓根 / tools/ / 临时目录 → 0/1/1)。
local _self = debug.getinfo(1, "S").source or "@tools/cli.lua"
local bootstrap = dofile((_self:gsub("\\", "/"):gsub("^@", ""):match("^(.*)/[^/]+$") or ".")
  .. "/foundation/bootstrap.lua")
local bootstrap_env = bootstrap.install(_self)

local tool_cli = require("foundation.tool_cli")
local boundary = require("foundation.platform_boundary")

-- 平台保证面(ADR 0083 / #234 F2):非 Windows 一律退 3,不进入任何子命令。
-- 判决渲染统一走 platform_boundary.unavailable_verdict(首行 `[cli] status=unavailable`),
-- 不在这里另写一套诊断格式。platform_verdict 用宿主平台;测试可注入平台判定经
-- dofile 驱动本文件而不必真换操作系统。
local platform_verdict = boundary.platform_verdict("cli")
if platform_verdict ~= nil then
  os.exit(boundary.emit(platform_verdict))
end

local raw_args = arg or {}
local name = raw_args[1]
if name == nil or tool_cli.is_help_flag(name) then
  io.write(_usage())
  os.exit(0)
end

local entry
for _, candidate in ipairs(commands) do
  if candidate.name == name then
    entry = candidate
    break
  end
end
if entry == nil then
  io.stderr:write("未知子命令: " .. name .. "\n\n" .. _usage())
  os.exit(2)
end

local cli_module = "packages." .. entry.pkg .. "." .. (entry.module or "cli")
local ok, cli = pcall(require, cli_module)
if not ok or type(cli) ~= "table" or type(cli.main) ~= "function" then
  io.stderr:write("子命令加载失败: " .. name .. " (" .. cli_module .. ")\n")
  io.stderr:write(tostring(cli) .. "\n\n")
  io.stderr:write(_usage())
  os.exit(2)
end

local rest = {}
for i = 2, #raw_args do
  rest[#rest + 1] = raw_args[i]
end

local env = {
  -- 自 bootstrap.install 起是绝对路径(此前是 ".");消费点按路径拼接,不假设相对形态。
  repo_root = bootstrap_env.repo_root,
  command = "lua tools/cli.lua " .. name,
}
local code = cli.main(rest, env)
os.exit(type(code) == "number" and code or 0)
