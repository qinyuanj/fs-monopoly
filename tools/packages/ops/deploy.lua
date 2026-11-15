-- Deploy lane (map #1 / #23 / #73):这是仓库内唯一部署脚本的 Lua 等价实现,把 payload
-- 按原样拷到本地 Eggy 目录。无 build-mode 概念;release 裁切是人工步骤,无专用脚本。
--
-- 行为真源:本文件自身(deploy.lua)。历史来源 deploy.ps1(373 行)已随 #384 删除,
-- 整体由本文件取代(ADR 0030)。
-- 运行在原生 Windows(ADR 0083),路径演算、文件系统与子进程原语一律取 foundation
-- (#222)。部署目标是 Windows 侧 Eggy 宿主目录:家目录直接取原生 %USERPROFILE%
-- (缺失再 `cmd /c echo %USERPROFILE%` 兜底),目录镜像走原生 robocopy;全程不经
-- WSL 互操作面(不靠子进程展开家目录、不做挂载点路径换算)。部署面独立于 bash 的选择
-- (ADR 0083 第 5 条)。
--
-- CLI 面:零参数、零开关、无 --help(继承被取代的 deploy.ps1 空 param(),#384);任何参数 → ERROR + exit 1。
-- 子命令入口:lua5.4 tools/cli.lua deploy 经 tools/packages/ops/cli.lua 壳转发,仅 --help/-h 在壳内
-- 消费返回 usage,其余参数原样透传,本语义不变。

local _module_name = ...
local _required = _module_name == "tools.packages.ops.deploy" or _module_name == "packages.ops.deploy"
-- 直跑(含 ops/cli.lua 子进程转发)时自举 package.path;被 require 时由调用方装好,不重复 install。
if not _required then
  dofile((debug.getinfo(1, "S").source:gsub("\\", "/"):gsub("^@", "")
    :match("^(.*)/[^/]+$") or ".") .. "/../../foundation/bootstrap.lua").install_here()
end

local text_lib = require("foundation.text")
local path_lib = require("foundation.path")
local shell_lib = require("foundation.shell")
local fs_lib = require("foundation.fs")
local env_lib = require("foundation.env")
local proc_lib = require("foundation.proc")
local boundary = require("foundation.platform_boundary")

local M = {}

-- foundation 以 (nil, err) 报错;部署流程以 error 终止,由 run_cli 统一打印 ERROR。
local function _check(ok, err)
  if not ok then
    error(err, 2)
  end
  return true
end

-- 默认命令执行:读回合并输出。外层子壳让命令自带的 2>/dev/null 先于 proc 追加的
-- `> out 2>&1` 生效(诊断噪音不混进 git porcelain 输出)。
local function _run(command)
  local result = proc_lib.run_command("(" .. command .. ")")
  return result and result.output or ""
end

-- 原生工具探测:目录镜像要 robocopy,它是部署唯一的外部依赖。探测走 foundation.proc
-- 的 command_exists(注入缝),缺一个就整体不可用(退 3)。
function M.detect_native_tools(command_exists)
  command_exists = command_exists or proc_lib.command_exists
  local missing = {}
  if not command_exists("robocopy") then
    missing[#missing + 1] = "robocopy"
  end
  return missing
end

-- 不可用判决的唯一出口:组装诊断、写 stderr、返回退出码(3)。deploy / deploy-diff /
-- sync-data 共用同一份渲染,不各写一份格式。
function M.emit_unavailable(tag, fields, lines, stderr)
  local verdict = boundary.unavailable_verdict(tag, fields, lines)
  local stream = stderr or io.stderr
  stream:write(verdict.message)
  if stream == io.stderr then
    stream:flush()
  end
  return verdict.exit_code
end

-- 家目录不可用的诊断正文(deploy / deploy-diff / sync-data 共用同一份口径)。
function M.home_unavailable_lines(detail)
  return {
    tostring(detail or "无法解析原生 Windows 家目录(%USERPROFILE%)。"),
    "本次未改动任何部署目录;退出码 " .. tostring(boundary.UNAVAILABLE_EXIT_CODE)
      .. " 表示环境不可用,不是部署失败。",
    "处理: 在原生 Windows 上运行(非 WSL),确认 %USERPROFILE% 已设置(cmd /c echo %USERPROFILE% 有输出)。",
  }
end

local function _script_dir()
  local source = path_lib.normalize_path((tostring(debug.getinfo(1, "S").source or ""):gsub("^@", "")))
  if not path_lib.is_absolute_path(source) then
    source = path_lib.join_path(env_lib.current_dir(), source)
  end
  return path_lib.parent_dir(source) or env_lib.current_dir()
end

-- 输出 / 错误工具(Write-Info / Exit-WithError 等价)。

function M.write_info(message)
  io.stdout:write(tostring(message or ""), "\n")
end

function M.exit_with_error(message)
  io.stderr:write("ERROR: " .. tostring(message or ""), "\n")
  os.exit(1)
end

local function _is_file(path)
  return fs_lib.path_exists(path) and not fs_lib.is_dir(path)
end

-- 家目录解析的唯一实现(ADR 0083 第 5 条;deploy / deploy-diff / sync-data / probe
-- 都只走这一处,不出现第二份):直接读原生 %USERPROFILE%,不经互操作层、不做挂载点
-- 路径换算;只有环境变量缺失时才用 `cmd /c echo %USERPROFILE%` 兜底。
-- 拿回的盘符路径只做正斜杠归一(盘符开头的 Windows 绝对路径形态),不做路径换算;
-- 不是盘符绝对路径(空、相对、UNC)一律返回 "",由调用方按「不可用」处理。
-- run 是命令执行注入缝(默认读回合并输出),getenv 是环境读取注入缝(默认 os.getenv)。
function M.resolve_windows_home_dir(run, getenv)
  run = run or _run
  getenv = getenv or os.getenv
  local profile = text_lib.trim(getenv("USERPROFILE") or "")
  if profile == "" then
    profile = text_lib.trim(run("cmd /c echo %USERPROFILE%"))
  end
  if profile == "" or not profile:match("^%a:") then
    return ""
  end
  return (path_lib.normalize_path(profile):gsub("/+$", ""))
end

-- 家目录:部署目标始终是 Windows 侧家目录;MONOPOLY_DEPLOY_HOME 只作为测试与沙箱的
-- 显式覆写面,不参与默认目标推导。
function M.resolve_home_dir(getenv)
  getenv = getenv or os.getenv
  local override = getenv("MONOPOLY_DEPLOY_HOME")
  if text_lib.trim(override) ~= "" then
    return (path_lib.normalize_path(override))
  end
  return M.resolve_windows_home_dir(nil, getenv)
end

-- 部署 payload(与 main 的拷贝清单一致)。部署按工作树原样拷贝,真机插桩靠的正是这一点,
-- 所以未提交改动只提示、不拦截:避免把半成品当成已提交版本做真机验证。
local _PAYLOAD_PATHS = { "src", "main.lua", "Data/UIManagerNodes.lua", "Data/Prefab.lua" }
M.PAYLOAD_PATHS = _PAYLOAD_PATHS
local _UNCOMMITTED_NOTICE_LIMIT = 10

-- 返回 payload 内未提交路径。用 -z:路径不加引号转义(空格、中文原样),条目以 NUL 分隔;
-- 重命名/复制条目后紧跟一个源路径字段,跳过它,只报新路径。
-- 没有 git 或不在仓库里时输出为空,返回空表:这是提示,不走「不可用」退 3。
function M.list_uncommitted_payload(project_root, run)
  run = run or _run
  local output = run("git -C " .. shell_lib.shell_quote(project_root)
    .. " -c core.quotepath=false status --porcelain -z -- " .. table.concat(_PAYLOAD_PATHS, " ") .. " 2>/dev/null")
  local paths = {}
  local skip_source = false
  for entry in tostring(output or ""):gmatch("[^%z]+") do
    if skip_source then
      skip_source = false
    else
      paths[#paths + 1] = entry:sub(4)
      skip_source = entry:sub(1, 1) == "R" or entry:sub(1, 1) == "C"
    end
  end
  return paths
end

function M.format_uncommitted_notice(paths)
  if #paths == 0 then
    return {}
  end
  local lines = {
    "WARNING: " .. tostring(#paths) .. " uncommitted payload file(s) deployed as-is (working tree, not HEAD):",
  }
  for i = 1, math.min(#paths, _UNCOMMITTED_NOTICE_LIMIT) do
    lines[#lines + 1] = "  " .. paths[i]
  end
  if #paths > _UNCOMMITTED_NOTICE_LIMIT then
    lines[#lines + 1] = "  ... and " .. tostring(#paths - _UNCOMMITTED_NOTICE_LIMIT) .. " more"
  end
  return lines
end

function M.resolve_normalized_path(path_text)
  if text_lib.trim(path_text) == "" then
    return ""
  end

  local candidate = tostring(path_text)
  if candidate:sub(1, 2) == "~/" or candidate:sub(1, 2) == "~\\" then
    candidate = path_lib.join_path(M.resolve_home_dir(), candidate:sub(3))
  end
  if path_lib.is_absolute_path(candidate) then
    return (path_lib.simplify_path(candidate):gsub("/+$", ""))
  end
  local full = path_lib.resolve_path(env_lib.current_dir(), candidate)
  return (full:gsub("/+$", ""))
end

-- 平台名:部署目标恒为 Windows 宿主;运行面必须是能起原生 robocopy 的原生 Windows。
-- 不可用时退 3(环境问题),不打印 ERROR(那不是部署失败)。
function M.resolve_platform_name()
  local missing = M.detect_native_tools()
  if #missing > 0 then
    os.exit(M.emit_unavailable("deploy", " step=native-tools", {
      "部署需要原生 Windows 工具:缺 " .. table.concat(missing, ", ") .. "。",
      "本次未改动任何部署目录;退出码 " .. tostring(boundary.UNAVAILABLE_EXIT_CODE)
        .. " 表示环境不可用,不是部署失败。",
      "处理: 在原生 Windows 上运行(非 WSL),确认 robocopy 在 PATH 上(C:/Windows/System32/Robocopy.exe)。",
    }))
  end
  return "win"
end

function M.join_lua_source_dir_name()
  -- "大富翁" = U+5927 U+5BCC U+7FC1(UTF-8),等价历史来源 deploy.ps1 的 [char]0x5927 拼接(已随 #384 删除)。
  return "LuaSource_" .. string.char(0xE5, 0xA4, 0xA7, 0xE5, 0xAF, 0x8C, 0xE7, 0xBF, 0x81)
end

function M.target_path_for_home(home_dir)
  return M.resolve_normalized_path(
    path_lib.join_path(home_dir, "Desktop", "dev", "eggy", M.join_lua_source_dir_name())
  )
end

-- 默认目标:<home>/Desktop/dev/eggy/LuaSource_大富翁。家目录取不到是不可用(退 3),
-- 不是部署失败(退 1),所以这里返回 (nil, 原因),由调用方按不可用判决处理。
function M.resolve_default_target_path(getenv)
  local home_dir = M.resolve_home_dir(getenv)
  if text_lib.trim(home_dir) == "" then
    return nil, "无法解析原生 Windows 家目录(%USERPROFILE%)。"
  end
  return M.target_path_for_home(home_dir)
end

function M.test_project_root(path_text)
  return _is_file(path_lib.join_path(path_text, "main.lua"))
    and fs_lib.is_dir(path_lib.join_path(path_text, "src"))
    and fs_lib.is_dir(path_lib.join_path(path_text, "tools"))
end

function M.resolve_project_root()
  local candidates = {
    path_lib.simplify_path(path_lib.join_path(_script_dir(), "../../..")),
    env_lib.current_dir(),
  }

  for _, candidate in ipairs(candidates) do
    if text_lib.trim(candidate) ~= "" and M.test_project_root(candidate) then
      return M.resolve_normalized_path(candidate)
    end
  end

  return M.resolve_normalized_path(candidates[1])
end

function M.reset_directory(path_text)
  _check(fs_lib.remove_path(path_text))
  _check(fs_lib.ensure_dir(path_text))
end

-- 与 #222 前的实现不同:find -type f 不跟随符号链接,`.lua` 后缀区分大小写(`.LUA`
-- 不计入);payload 无符号链接、无大写后缀,统计不变。
local function _collect_lua_files(path)
  local files, err = proc_lib.collect_lua_files(path)
  _check(files, err)
  return files
end

-- robocopy 的退出码不是 0/非 0:0..7 都是成功(0 无变化 / 1 有拷贝 / 2 有额外项被清 /
-- 3 两者都有 …),>=8 才是失败(8 部分失败,16 致命错误)。照搬 0/非 0 会把正常部署判成失败。
local _ROBOCOPY_SUCCESS_MAX = 7

-- MSYS 系 bash(Git Bash / MSYS2)会把 /MIR 一类开关当成 POSIX 路径改写成
-- C:/Program Files/Git/MIR(实测),用这两个变量关掉参数转换;MSYS bash 本身不改写,
-- 多设一个变量无副作用。部署面因此不依赖某个特定 bash 的改写策略(ADR 0083 第 5 条)。
local _ROBOCOPY_ENV = "MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 "
local _ROBOCOPY_FLAGS = { "/MIR", "/NFL", "/NDL", "/NJH", "/NJS", "/NP" }

-- 镜像拷贝的唯一命令构造:/MIR 的可观察结果与历史实现一致——目标侧陈旧文件与目录
-- 消失,源侧隐藏项与空目录保留,字节原样;/NFL /NDL /NJH /NJS /NP 只压输出噪音。
function M.robocopy_command(source_dir, target_dir)
  local source = path_lib.normalize_path(source_dir):gsub("/+$", "")
  local target = path_lib.normalize_path(target_dir):gsub("/+$", "")
  local parts = {
    _ROBOCOPY_ENV .. "robocopy",
    shell_lib.shell_quote(source),
    shell_lib.shell_quote(target),
  }
  for _, flag in ipairs(_ROBOCOPY_FLAGS) do
    parts[#parts + 1] = flag
  end
  return table.concat(parts, " ")
end

function M.robocopy_succeeded(code)
  return type(code) == "number" and code >= 0 and code <= _ROBOCOPY_SUCCESS_MAX
end

-- robocopy 执行缝:返回退出码。测试注入桩,不真跑 robocopy。
function M.run_robocopy(command)
  local result = proc_lib.run_command(command)
  return result and result.code or 1
end

-- 目录镜像:交给原生 robocopy /MIR。源缺失时先报错,目标保持不动。
function M.copy_directory_tree(source_dir, target_dir)
  if not fs_lib.is_dir(source_dir) then
    error("Source directory does not exist: " .. tostring(source_dir))
  end
  local command = M.robocopy_command(source_dir, target_dir)
  local code = M.run_robocopy(command)
  if not M.robocopy_succeeded(code) then
    error("robocopy failed with exit code " .. tostring(code) .. ": " .. command)
  end
  return true
end

function M.copy_file_with_parent_dir(source_path, target_path)
  return _check(fs_lib.copy_file(source_path, target_path))
end

-- 拷贝清单唯一真源是 PAYLOAD_PATHS:deploy-diff 按同一张表比对,两边不会各记一份。
function M.copy_payload(project_root, target_path)
  for _, relative_path in ipairs(_PAYLOAD_PATHS) do
    local source = path_lib.join_path(project_root, relative_path)
    local target = path_lib.join_path(target_path, relative_path)
    if fs_lib.is_dir(source) then
      M.copy_directory_tree(source, target)
    else
      M.copy_file_with_parent_dir(source, target)
    end
  end
end

-- 统计函数。

-- #527:行首块注释(--[[ / --[==[ 等长括号形式)的内部行不是有效代码——
-- 每个 src 文件尾部的 mutate4lua manifest 即此形态,朴素口径曾虚高约 40%。
-- 行内开口(代码行尾的 --[[@as T]] 之类)不做状态跟踪:同仓库内该类注解
-- 均同行闭合,不影响口径。
function M.get_effective_lua_line_count_for_file(path_text)
  if not _is_file(path_text) then
    return 0
  end

  local count = 0
  local block_close = nil
  for line in io.lines(path_text) do
    local text = line
    if block_close ~= nil then
      local _, close_end = text:find(block_close, 1, true)
      if close_end == nil then
        text = ""
      else
        text = text:sub(close_end + 1)
        block_close = nil
      end
    end
    local trimmed = text_lib.trim(text)
    local _, open_end, equals = trimmed:find("^%-%-%[(=*)%[")
    if open_end ~= nil then
      block_close = "]" .. equals .. "]"
      local _, inline_close_end = trimmed:find(block_close, open_end + 1, true)
      if inline_close_end ~= nil then
        trimmed = text_lib.trim(trimmed:sub(inline_close_end + 1))
        block_close = nil
      else
        trimmed = ""
      end
    end
    if trimmed ~= "" and trimmed:sub(1, 2) ~= "--" then
      count = count + 1
    end
  end
  return count
end

function M.get_effective_lua_line_count_for_dir(path_text)
  if not fs_lib.is_dir(path_text) then
    return 0
  end

  local total = 0
  for _, file_path in ipairs(_collect_lua_files(path_text)) do
    total = total + M.get_effective_lua_line_count_for_file(file_path)
  end
  return total
end

function M.get_lua_file_count(path_text)
  if not fs_lib.path_exists(path_text) then
    return 0
  end
  if _is_file(path_text) then
    return 1
  end
  return #_collect_lua_files(path_text)
end

local function _error_text(err)
  if type(err) == "string" then
    return err
  end
  if type(err) == "table" and err.message ~= nil then
    return tostring(err.message)
  end
  return tostring(err)
end

-- 主流程:顺序与输出逐行复刻历史来源 deploy.ps1(已随 #384 删除)。
local function main()
  local project_root = M.resolve_project_root()
  local resolved_platform = M.resolve_platform_name()
  local target_source, home_err = M.resolve_default_target_path()
  if target_source == nil then
    os.exit(M.emit_unavailable("deploy", " step=home", M.home_unavailable_lines(home_err)))
  end
  local target_path = M.resolve_normalized_path(target_source)

  _check(fs_lib.ensure_dir(target_path))

  M.write_info("======================================")
  M.write_info("Starting project deployment")
  M.write_info("======================================")
  M.write_info("Project root: " .. tostring(project_root))
  M.write_info("Target path: " .. tostring(target_path))
  M.write_info("Target platform: " .. tostring(resolved_platform) .. " (native Windows via robocopy)")
  M.write_info("")
  M.write_info("--------------------------------------")
  M.write_info("Deploy target: " .. tostring(target_path))
  M.write_info("--------------------------------------")
  for _, line in ipairs(M.format_uncommitted_notice(M.list_uncommitted_payload(project_root))) do
    M.write_info(line)
  end

  M.copy_payload(project_root, target_path)

  -- 统计读本地源侧:拷贝是 as-is,文件与有效行数量等价。
  local total_files =
    M.get_lua_file_count(path_lib.join_path(project_root, "src"))
    + M.get_lua_file_count(path_lib.join_path(project_root, "main.lua"))
    + M.get_lua_file_count(path_lib.join_path(project_root, "Data/UIManagerNodes.lua"))
    + M.get_lua_file_count(path_lib.join_path(project_root, "Data/Prefab.lua"))
  local total_effective_line_count =
    M.get_effective_lua_line_count_for_dir(path_lib.join_path(project_root, "src"))
    + M.get_effective_lua_line_count_for_file(path_lib.join_path(project_root, "main.lua"))
    + M.get_effective_lua_line_count_for_file(path_lib.join_path(project_root, "Data/UIManagerNodes.lua"))
    + M.get_effective_lua_line_count_for_file(path_lib.join_path(project_root, "Data/Prefab.lua"))

  M.write_info("")
  M.write_info("Lua Files: " .. tostring(total_files))
  M.write_info("Effective LOC: " .. tostring(total_effective_line_count))
  M.write_info("")
  M.write_info("======================================")
  M.write_info("Deployment completed!")
  M.write_info("  " .. tostring(target_path))
  M.write_info("  Lua Files: " .. tostring(total_files) .. ", Effective LOC: " .. tostring(total_effective_line_count))
  M.write_info("======================================")
  os.exit(0)
end

local function run_cli()
  local extra_args = {}
  for index = 1, #arg do
    extra_args[#extra_args + 1] = arg[index]
  end
  if #extra_args > 0 then
    M.exit_with_error("Unexpected argument: " .. table.concat(extra_args, " "))
  end

  local ok, err = pcall(main)
  if not ok then
    M.exit_with_error(_error_text(err))
  end
  return 0
end

if _required then
  return M
end

os.exit(run_cli())
