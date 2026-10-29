-- tools/cli.lua —— 工具链唯一对外面（#300）
--
-- 用法:
--   lua5.4 tools/cli.lua <子命令> [args...]
--   lua5.4 tools/cli.lua --help | -h
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
local commands = {
  { name = "verify",            pkg = "verify",             summary = "质量门禁编排器(默认 slim;--tooling 加跑工具链测试)" },
  { name = "spec-lane",         pkg = "spec_lane",          summary = "测试车道运行器(--profile behavior|tooling)" },
  { name = "dry",               pkg = "dry",                summary = "结构重复检测(邻接 .uml-viewer/dryer;写 .metrics/dry.edn)" },
  { name = "uml",               pkg = "uml_quality",        summary = "邻接 uml-viewer 入口(check/crap/mutate/ir/view;受控 Lua 环境)" },
  { name = "lint",              pkg = "lint",              summary = "luacheck 静态检查(默认扫 src/test/tools)" },
  { name = "deploy",            pkg = "ops",                summary = "部署到 Windows 侧 Eggy 目录(WSL 写 /mnt/c;零参数)" },
  { name = "sync-data",         pkg = "data_sync",          summary = "从部署目录回同步导出(Data;EggyAPI/EggyEditorAPI 存根)" },
  { name = "probe",             pkg = "probe",              summary = "试玩态探针(经 editor-cli 在游戏内执行 lua 文件,取回 probe(...) 输出)" },
  { name = "gift-code",         pkg = "gift_code",          summary = "礼包码补偿码生成(new:随机码 → 哈希入码表,明文只打印一次)" },
  { name = "clean",             pkg = "clean",              summary = "清生成物(build/tmp/luacov 等)" },
}

local function _module_dir()
  local source = debug.getinfo(1, "S").source or "@tools/cli.lua"
  local normalized = tostring(source):gsub("\\", "/"):gsub("^@", "")
  return normalized:match("^(.*)/[^/]+$") or "tools"
end

-- 脚本自定位 repo_root:source 为 "@tools/cli.lua"(从仓库根跑)时返回 "."。
local function _repo_root()
  local dir = _module_dir()
  return dir:match("^(.*)/[^/]+$") or "."
end

local function _usage()
  local lines = {
    "用法: lua5.4 tools/cli.lua <子命令> [args...]",
    "",
    "子命令（封闭命令集）：",
  }
  for _, entry in ipairs(commands) do
    lines[#lines + 1] = string.format("  %-18s %s", entry.name, entry.summary)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "退出码:0 成功 / 1 真实失败 / 2 用法错误 / 3 平台或工具不可用(先查环境再重跑)"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "用法提示:"
  lines[#lines + 1] = "  lua5.4 tools/cli.lua <子命令> --help   子命令帮助(包内 usage 真源)"
  return table.concat(lines, "\n") .. "\n"
end

local root = _repo_root()
-- 包内 cli.lua 的装载面:模块名自带 packages. 前缀(#300 决议
-- require("packages.<pkg>.cli")),path 拼到 tools/ 一层即可命中
-- tools/packages/<pkg>/cli.lua(命名契约,#300 Q4——伪入口文件名不匹配
-- packages.<name>.cli,物理进不了路由)。?/init.lua 让包内 cli 能 require 目录式
-- 包(如 uml ir 用的 packages.arch_policy)。
package.path = package.path .. ";" .. root .. "/tools/?.lua;" .. root .. "/tools/?/init.lua"

-- 入口解释器预检(#191 用户故事 3):本机 PATH 上的 `lua` 是 5.1,兄弟仓依赖它,
-- 所以入口不靠改全局别名,而是显式要求 `lua5.4`;误用别的解释器时立即退 1,
-- 而不是让 5.1 语义悄悄跑完一整套测试。
if _VERSION ~= "Lua 5.4" then
  io.stderr:write("Lua 5.4 interpreter required; run `lua5.4 tools/cli.lua <子命令>` (found " .. tostring(_VERSION) .. ")\n")
  os.exit(1)
end

local tool_cli = require("foundation.tool_cli")

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

local ok, cli = pcall(require, "packages." .. entry.pkg .. ".cli")
if not ok or type(cli) ~= "table" or type(cli.main) ~= "function" then
  io.stderr:write("子命令加载失败: " .. name .. " (packages." .. entry.pkg .. ".cli)\n")
  io.stderr:write(tostring(cli) .. "\n\n")
  io.stderr:write(_usage())
  os.exit(2)
end

local rest = {}
for i = 2, #raw_args do
  rest[#rest + 1] = raw_args[i]
end

local env = {
  repo_root = root,
  command = "lua5.4 tools/cli.lua " .. name,
}
local code = cli.main(rest, env)
os.exit(type(code) == "number" and code or 0)
