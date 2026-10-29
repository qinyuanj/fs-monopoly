-- packages/clean/cli.lua —— clean 子命令(吸收原 Makefile clean 面;
-- Makefile/project.mk 退役,清理语义原样搬家,清单与生产者一一对应关系不变)。
--
-- 统一接口形态(#300 决议):本文件 return 纯接口模块:
--   M.main(args, env) -> 退出码(0 成功 / 1 业务失败 / 2 用法错误)
--   M.usage()         -> 完整 usage 文本(包内单一真源,顶层 <cmd> --help 转发)
--
-- 清单与生产者对应:build/ tmp/ 为本地构建产物;
-- luacov.* 是 luacov 默认落点的残留
-- (uml crap 的 crapper 经 luacov 采集覆盖率)。
-- 仓内不再有项目工具缓存:工具模块一律从受控 Lua 环境装载,clean 只清仓内
-- 生成物。
--
-- 实现:WSL Ubuntu 单平台(ADR 0073)。目录与文件都经 foundation.fs.remove_path
-- 删(整树删 / 删文件,未命中静默成功);luacov 的 glob 由 foundation.proc 枚举
-- 仓根候选、Lua 模式按旧 glob 口径筛,只看仓根不递归,与被取代的 Makefile
-- `rm -rf` / `rm -f` 清单同一目标集。
local M = {}

local fs_lib = require("foundation.fs")
local path_lib = require("foundation.path")
local proc = require("foundation.proc")
local shell_lib = require("foundation.shell")
local tool_cli = require("foundation.tool_cli")

local _CLEAN_DIRS = { "build", "tmp" }
local _CLEAN_FILES = {
  "luacov.stats.out",
  "luacov.report.out",
}
-- 旧 glob `luacov.*.stats.out` / `luacov.*.report.out` 的同义 Lua 模式。
local _CLEAN_FILE_PATTERNS = {
  "^luacov%..*%.stats%.out$",
  "^luacov%..*%.report%.out$",
}

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua clean",
    "",
    "清生成物:build/ tmp/、luacov 残留。",
    "",
  }, "\n") .. "\n"
end

-- 仓根下按 _CLEAN_FILE_PATTERNS 命中的文件名(不含目录)。
-- 枚举用 `find -maxdepth 1 -name 'luacov.*'`(单层、含隐藏项),再由 Lua 模式复核
-- (与旧 glob 口径同一目标集)。目录不存在时 find 非零,交给调用方报错。
local function _glob_targets(repo_root)
  local result = proc.run_command("find " .. shell_lib.shell_quote(path_lib.normalize_path(repo_root))
    .. " -maxdepth 1 -type f -name 'luacov.*' -print 2>/dev/null")
  if not result.ok then
    return nil, "枚举 luacov 残留失败(exit " .. tostring(result.code) .. "): " .. tostring(result.output)
  end
  local names = {}
  for line in (tostring(result.output or "") .. "\n"):gmatch("(.-)\n") do
    -- find 给的是完整路径,清单按仓根相对名比对。
    local name = line:gsub("\r$", ""):match("([^/]+)$") or ""
    for _, file_pattern in ipairs(_CLEAN_FILE_PATTERNS) do
      if name:match(file_pattern) then
        names[#names + 1] = name
        break
      end
    end
  end
  return names
end

local function _remove_all(repo_root, relative_paths)
  for _, relative in ipairs(relative_paths) do
    local ok, err = fs_lib.remove_path(path_lib.join_path(repo_root, relative))
    if not ok then
      io.stderr:write("clean 失败: " .. tostring(err) .. "\n")
      return false
    end
  end
  return true
end

function M.main(args, env)
  local first = (args or {})[1]
  if tool_cli.is_help_flag(first) then
    io.write(M.usage())
    return 0
  end
  if first ~= nil then
    io.stderr:write("未知参数: " .. tostring(first) .. "\n\n" .. M.usage())
    return 2
  end

  local repo_root = (env and env.repo_root) or "."
  local dirs = { table.unpack(_CLEAN_DIRS) }

  if not _remove_all(repo_root, dirs) then
    return 1
  end
  local globbed, glob_err = _glob_targets(repo_root)
  if globbed == nil then
    io.stderr:write("clean 失败: " .. glob_err .. "\n")
    return 1
  end
  local files = { table.unpack(_CLEAN_FILES) }
  for _, name in ipairs(globbed) do
    files[#files + 1] = name
  end
  if not _remove_all(repo_root, files) then
    return 1
  end
  return 0
end

return M
