-- tools/cli.lua —— 工具链唯一对外面（#300）
--
-- 用法:
--   lua tools/cli.lua <子命令> [args...]
--   lua tools/cli.lua --help | -h
--
-- 调度机制:顶层静态路由表 commands(封闭命令集,子命令集合与「不进」清单以
-- 以本文件的封闭命令表为准；伪入口 / swarm / loc 不进）——查表 →
-- require("packages.<pkg>.cli") → cli.main(args, env) → 顶层统一 os.exit。
--
-- 退出码约定(#300 Q2):0 = 成功 / 1 = 业务失败 / 2 = 用法错误(未知子命令、
-- require 失败)/ 3 = 不可用(声明的平台保证边界之外,#96)。第 4 个码是必要的:
-- 工具自举的网络失败沿用退 3(#112),与「跑了但失败」区分。
-- 包内处理 --help/-h 并返回 0。
--
-- 骨架期(#304):包内 cli.lua 统一接口形态落地为骨架约定
-- (return { main = function(args, env) -> 退出码, usage = function() -> string }),
-- 各子命令转发到现状入口(旧物理位置不动);包迁票逐个替换为包内实现。
local commands = {
  { name = "verify",            pkg = "verify",             summary = "质量门禁编排器(默认 slim;--tooling 加跑工具链测试)" },
  { name = "spec-lane",         pkg = "spec_lane",          summary = "测试车道运行器(--profile behavior|tooling)" },
  { name = "dry",               pkg = "dry",                summary = "结构重复检测(邻接 .uml-viewer/dryer;写 .metrics/dry.edn)" },
  { name = "uml",               pkg = "uml_quality",        summary = "邻接 uml-viewer 入口(check/crap/mutate/ir/view;项目缓存钉死)" },
  { name = "lint",              pkg = "lint",              summary = "luacheck 静态检查(默认扫 src/test/tools)" },
  { name = "deploy",            pkg = "ops",                summary = "部署到本地 Eggy 目录(原生 Windows;零参数)" },
  { name = "sync-data",         pkg = "data_sync",          summary = "从部署目录回同步导出(Data;EggyAPI/EggyEditorAPI 存根)" },
  { name = "clean",             pkg = "clean",              summary = "清生成物(build/tmp/luacov 等)",              action = "clean" },
  { name = "distclean",         pkg = "clean",              summary = "clean 之上再清 .toolcache", action = "distclean" },
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
    "用法: lua tools/cli.lua <子命令> [args...]",
    "",
    "子命令（封闭命令集）：",
  }
  for _, entry in ipairs(commands) do
    lines[#lines + 1] = string.format("  %-18s %s", entry.name, entry.summary)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "用法提示:"
  lines[#lines + 1] = "  lua tools/cli.lua <子命令> --help   子命令帮助(包内 usage 真源)"
  return table.concat(lines, "\n") .. "\n"
end

local root = _repo_root()
-- 包内 cli.lua 的装载面:模块名自带 packages. 前缀(#300 决议
-- require("packages.<pkg>.cli")),path 拼到 tools/ 一层即可命中
-- tools/packages/<pkg>/cli.lua(命名契约,#300 Q4——伪入口文件名不匹配
-- packages.<name>.cli,物理进不了路由)。?/init.lua 让包内 cli 能 require 目录式
-- 包(如 uml ir 用的 packages.arch_policy)。
package.path = package.path .. ";" .. root .. "/tools/?.lua;" .. root .. "/tools/?/init.lua"

local raw_args = arg or {}
local name = raw_args[1]
if name == nil or name == "--help" or name == "-h" then
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
  command = "lua tools/cli.lua " .. name,
  action = entry.action,
}
local code = cli.main(rest, env)
os.exit(type(code) == "number" and code or 0)
