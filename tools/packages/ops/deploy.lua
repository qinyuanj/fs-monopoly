-- Deploy lane (map #1 / #23 / #73):这是仓库内唯一部署脚本的 Lua 等价实现,把 payload
-- 按原样拷到本地 Eggy 目录。无 build-mode 概念;release 裁切是人工步骤,无专用脚本。
--
-- 行为真源:本文件自身(deploy.lua)。历史来源 deploy.ps1(373 行)已随 #384 删除,
-- 整体由本文件取代(ADR 0030);正文中 deploy.ps1 行号仅作历史坐标保留。
-- 运行在 WSL Ubuntu(ADR 0073),以 Lua 5.4 标准库 + POSIX 原语完成目标解析、
-- 目录镜像与逐文件复制;不加载额外文件系统依赖。部署目标仍是 Windows 侧 Eggy
-- 宿主目录:经 cmd.exe 取 %USERPROFILE%,再用 wslpath -u 换算成 /mnt/c/... 路径。
--
-- CLI 面:零参数、零开关、无 --help(继承被取代的 deploy.ps1 空 param(),#384);任何参数 → ERROR + exit 1。
-- 子命令入口:lua5.4 tools/cli.lua deploy 经 tools/packages/ops/cli.lua 壳转发,仅 --help/-h 在壳内
-- 消费返回 usage,其余参数原样透传,本语义不变。

local M = {}

local function _trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function _is_blank(value)
  return _trim(value) == ""
end

local function _normalize_path(value)
  return tostring(value or ""):gsub("\\", "/")
end

-- 运行平台:WSL 的判据是「Linux 且能起 cmd.exe + wslpath」。缺任一即不可用
-- (退 3),不把环境问题当成部署失败。
local function _actual_is_windows()
  return package.config:sub(1, 1) == "\\"
end

local function _exit_status(ok, _, code)
  if type(ok) == "number" then
    return ok == 0, ok
  end
  if ok == true then
    return true, code or 0
  end
  return false, code or 1
end

local function _popen(command)
  local handle = io.popen(command, "r")
  if handle == nil then
    return ""
  end
  local output = handle:read("*a") or ""
  handle:close()
  return output
end

-- 真 cwd 以 `pwd -L` 为准;继承的 PWD 可能已被子进程 cwd 改动作废
-- (Python subprocess(cwd=...) 不更新 PWD),只作兜底。
local function _current_dir()
  local printed = _normalize_path(_trim(_popen("pwd -L 2>/dev/null")))
  if printed ~= "" then
    return printed
  end
  local value = os.getenv("PWD")
  if value ~= nil and value ~= "" then
    return _normalize_path(_trim(value))
  end
  return ""
end

-- POSIX 单引号;拒绝换行与 NUL,避免参数被解释成第二条命令。
local function _shell_arg(value)
  local text = tostring(value or "")
  assert(not text:find("[\r\n%z]"), "Unsupported command path")
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- 纯 Lua 判定:io.open 对目录同样成功,故目录用 `path/.` 探测。
local function _openable(path)
  local handle = io.open(path, "rb")
  if handle == nil then
    return false
  end
  handle:close()
  return true
end

local function _path_exists(path)
  if path == nil or path == "" then
    return false
  end
  local text = _normalize_path(path)
  if _openable(text) or _openable(text .. "/.") then
    return true
  end
  return os.rename(text, text) ~= nil
end

local function _path_is_dir(path)
  if path == nil or path == "" then
    return false
  end
  return _openable(_normalize_path(path) .. "/.")
end

local function _path_is_file(path)
  if path == nil or path == "" then
    return false
  end
  return _openable(path) and not _openable(_normalize_path(path) .. "/.")
end

local function _ensure_dir(path)
  if path == nil or path == "" then
    return true
  end
  local ok, kind, code = os.execute("mkdir -p " .. _shell_arg(_normalize_path(path)))
  local success = _exit_status(ok, kind, code)
  if not success then
    error("Failed to create directory: " .. tostring(path))
  end
  return true
end

local function _remove_path(path)
  if not _path_exists(path) then
    return true
  end
  local ok, kind, code = os.execute("rm -rf " .. _shell_arg(_normalize_path(path)))
  local success = _exit_status(ok, kind, code)
  if not success then
    error("Failed to remove path: " .. tostring(path))
  end
  return true
end

local function _command_available(name)
  local ok, kind, code = os.execute("command -v " .. _shell_arg(name) .. " >/dev/null 2>&1")
  return _exit_status(ok, kind, code)
end

-- 一次性探测 WSL 的互操作面:cmd.exe(取 %USERPROFILE%)与 wslpath(路径换算)。
-- 两者都在才谈得上「在 WSL 里往 Windows 部署」;缺一个就整体不可用。
function M.detect_interop()
  local missing = {}
  if not _command_available("cmd.exe") then
    missing[#missing + 1] = "cmd.exe"
  end
  if not _command_available("wslpath") then
    missing[#missing + 1] = "wslpath"
  end
  return missing
end

local function _join_path(...)
  local result = ""
  for index = 1, select("#", ...) do
    local segment = _normalize_path(select(index, ...))
    if result == "" then
      result = segment
    elseif segment ~= "" then
      result = result:gsub("/+$", "") .. "/" .. segment:gsub("^/+", "")
    end
  end
  return result
end

-- GetFullPath 等价(绝对路径的 . 与 .. 折叠);resolve_normalized_path 在调用前
-- 已保证 candidate 绝对化,这里只做演算。

-- 拆出路径前缀:Windows 盘符(如 "C:")、POSIX 根 "/"、或空(相对路径)。
local function _split_path_prefix(normalized)
  if normalized:match("^%a:/") then
    return normalized:sub(1, 3), normalized:sub(4)
  end
  if normalized:sub(1, 1) == "/" then
    return "/", normalized:sub(2)
  end
  return "", normalized
end

-- 折叠 "." 与 ".." 段:相对路径(prefix == "")保留前导 "..",绝对路径在根处截断。
local function _fold_path_segments(remainder, keep_leading_dotdot)
  local parts = {}
  for segment in (remainder .. "/"):gmatch("(.-)/") do
    if segment ~= "" and segment ~= "." then
      if segment == ".." then
        if #parts > 0 and parts[#parts] ~= ".." then
          parts[#parts] = nil
        elseif keep_leading_dotdot then
          parts[#parts + 1] = segment
        end
      else
        parts[#parts + 1] = segment
      end
    end
  end
  return table.concat(parts, "/")
end

-- 前缀与折叠后的段重拼:空段时根 "/" 折叠回 "/",盘符前缀原样返回。
local function _reassemble_path(prefix, simplified)
  if prefix == "" then
    return simplified
  end
  if simplified == "" then
    return prefix == "/" and "/" or prefix
  end
  return prefix == "/" and "/" .. simplified or prefix .. simplified
end

local function _simplify_path(value)
  local normalized = _normalize_path(value)
  local prefix, remainder = _split_path_prefix(normalized)
  return _reassemble_path(prefix, _fold_path_segments(remainder, prefix == ""))
end

local function _get_full_path(value)
  return _simplify_path(value)
end

local function _is_path_rooted(value)
  local normalized = _normalize_path(value)
  return normalized:match("^%a:") ~= nil or normalized:match("^[/\\]") ~= nil
end

-- .NET ExpandEnvironmentVariables 等价:%NAME% 展开,未定义变量原样保留。
local function _expand_environment_variables(value)
  return (tostring(value or ""):gsub("%%([^%%]+)%%", function(name)
    local env_value = os.getenv(name)
    if env_value == nil then
      return "%" .. name .. "%"
    end
    return env_value
  end))
end

local function _script_path()
  local source = debug.getinfo(1, "S").source or ""
  local value = _normalize_path(tostring(source):gsub("^@", ""))
  if value == "" then
    value = tostring(arg and arg[0] or "")
  end
  if not _is_path_rooted(value) then
    value = _join_path(_current_dir(), value)
  end
  return value
end

local function _script_dir()
  local script = _script_path()
  return script:match("^(.*)/[^/]+$") or _current_dir()
end

-- 文本 / 输出 / 错误工具(Get-Text / Write-Info / Exit-WithError 等价)。

function M.get_text(zh, en)
  return tostring(zh or "") .. " / " .. tostring(en or "")
end

function M.write_info(message)
  io.stdout:write(tostring(message or ""), "\n")
end

function M.exit_with_error(message)
  io.stderr:write("ERROR: " .. tostring(message or ""), "\n")
  os.exit(1)
end

-- 路径工具。

function M.normalize_path_text(value)
  return _normalize_path(value)
end

-- Windows 侧家目录从 %USERPROFILE% 动态解析,不在代码里硬编码用户名:
-- 在 /mnt/c 下起 cmd.exe(UNC 工作目录会让 cmd 回落到 C:\Windows,所以先 cd
-- 到 /mnt/c),再经 wslpath -u 换算成 WSL 路径。任何一步失败都返回 "",由调用方
-- 按「不可用」处理。run 是命令执行注入缝(默认 io.popen 读全部输出),供测试替身。
function M.resolve_windows_home_dir(run)
  run = run or _popen
  local profile = _trim(run("cd /mnt/c 2>/dev/null && cmd.exe /d /c 'echo %USERPROFILE%' 2>/dev/null"))
  if _is_blank(profile) or not profile:match("^%a:") then
    return ""
  end
  local converted = _trim(run("wslpath -u " .. _shell_arg(profile) .. " 2>/dev/null"))
  if _is_blank(converted) or converted:sub(1, 1) ~= "/" then
    return ""
  end
  return (M.normalize_path_text(converted))
end

-- 家目录:部署目标始终是 Windows 侧家目录;WSL 的 $HOME 只作为测试与沙箱的
-- 显式覆写面(环境变量 MONOPOLY_DEPLOY_HOME),不参与默认目标推导。
function M.resolve_home_dir()
  local override = os.getenv("MONOPOLY_DEPLOY_HOME")
  if not _is_blank(override) then
    return (M.normalize_path_text(override))
  end
  return M.resolve_windows_home_dir()
end

-- 部署 payload(与 main 的拷贝清单一致)。部署按工作树原样拷贝,真机插桩靠的正是这一点,
-- 所以未提交改动只提示、不拦截:避免把半成品当成已提交版本做真机验证。
local _PAYLOAD_PATHS = { "src", "main.lua", "Data/UIManagerNodes.lua", "Data/Prefab.lua" }
local _UNCOMMITTED_NOTICE_LIMIT = 10

-- 返回 payload 内未提交路径。用 -z:路径不加引号转义(空格、中文原样),条目以 NUL 分隔;
-- 重命名/复制条目后紧跟一个源路径字段,跳过它,只报新路径。
-- 没有 git 或不在仓库里时输出为空,返回空表:这是提示,不走「不可用」退 3。
function M.list_uncommitted_payload(project_root, run)
  run = run or _popen
  local output = run("git -C " .. _shell_arg(project_root)
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
  if _is_blank(path_text) then
    return ""
  end

  local candidate = _expand_environment_variables(tostring(path_text))
  if candidate:sub(1, 2) == "~/" or candidate:sub(1, 2) == "~\\" then
    candidate = _join_path(M.resolve_home_dir(), candidate:sub(3))
  end
  if not _is_path_rooted(candidate) then
    candidate = _join_path(_current_dir(), candidate)
  end
  local full = M.normalize_path_text(_get_full_path(candidate))
  return (full:gsub("/+$", ""))
end

-- 平台判定入口。

function M.test_is_windows_host()
  return _actual_is_windows()
end

-- 平台名:部署目标恒为 Windows 宿主;运行面必须是能起 cmd.exe + wslpath 的 WSL。
-- 不可用时退 3(环境问题),不打印 ERROR(那不是部署失败)。
function M.resolve_platform_name()
  local missing = M.detect_interop()
  if #missing > 0 then
    local boundary = dofile(_script_dir() .. "/../../foundation/platform_boundary.lua")
    local verdict = boundary.unavailable_verdict("deploy", " step=interop", {
      "部署需要 WSL 互操作面:缺 " .. table.concat(missing, ", ") .. "。",
      "本次未改动任何部署目录;退出码 " .. boundary.UNAVAILABLE_EXIT_CODE
        .. " 表示环境不可用,不是部署失败。",
      "处理: 在 WSL Ubuntu 中运行,并确认 /mnt/c 已挂载(cmd.exe 与 wslpath 可见)。",
    })
    io.stderr:write(verdict.message)
    io.stderr:flush()
    os.exit(verdict.exit_code)
  end
  return "win"
end

function M.join_lua_source_dir_name()
  -- "大富翁" = U+5927 U+5BCC U+7FC1(UTF-8),等价历史来源 deploy.ps1 的 [char]0x5927 拼接(已随 #384 删除)。
  return "LuaSource_" .. string.char(0xE5, 0xA4, 0xA7, 0xE5, 0xAF, 0x8C, 0xE7, 0xBF, 0x81)
end

function M.resolve_default_target_path(resolved_platform)
  local home_dir = M.resolve_home_dir()
  if _is_blank(home_dir) then
    M.exit_with_error("Cannot resolve the Windows home directory (%USERPROFILE%) for the default deploy target.")
  end

  if resolved_platform == "win" then
    return M.resolve_normalized_path(
      _join_path(_join_path(_join_path(_join_path(home_dir, "Desktop"), "dev"), "eggy"), M.join_lua_source_dir_name())
    )
  end
  M.exit_with_error("No default deploy target is configured for this platform.")
end

function M.test_project_root(path_text)
  return _path_is_file(_join_path(path_text, "main.lua"))
    and _path_is_dir(_join_path(path_text, "src"))
    and _path_is_dir(_join_path(path_text, "tools"))
end

function M.resolve_project_root()
  local candidates = {
    _get_full_path(_join_path(_script_dir(), "../../..")),
    _current_dir(),
  }

  for _, candidate in ipairs(candidates) do
    if not _is_blank(candidate) and M.test_project_root(candidate) then
      return M.resolve_normalized_path(candidate)
    end
  end

  return M.resolve_normalized_path(candidates[1])
end

function M.reset_directory(path_text)
  if _path_exists(path_text) then
    _remove_path(path_text)
  end
  _ensure_dir(path_text)
end

-- 单层条目枚举(含隐藏项):`find -mindepth 1 -maxdepth 1` 一次调用同时拿到
-- 文件与目录,中文与空格文件名按 NUL 分隔原样读回。
local function _list_entries(path)
  if not _path_exists(path) then
    error("Path does not exist: " .. tostring(path))
  end
  local output = _popen("find " .. _shell_arg(_normalize_path(path))
    .. " -mindepth 1 -maxdepth 1 -print0 2>/dev/null")
  local entries = {}
  for full in (output .. "\0"):gmatch("(.-)\0") do
    if full ~= "" then
      local name = full:match("([^/]+)$") or full
      entries[#entries + 1] = { name = name, is_dir = _path_is_dir(full) }
    end
  end
  return entries
end

local function _collect_lua_files(path, result)
  for _, entry in ipairs(_list_entries(path)) do
    local full = _join_path(path, entry.name)
    if entry.is_dir then
      _collect_lua_files(full, result)
    elseif entry.name:lower():match("%.lua$") ~= nil then
      result[#result + 1] = full
    end
  end
  return result
end

-- 二进制逐块复制(不按行读:行读会把 \r 与二进制内容改写掉)。
local function _copy_file_bytes(source, target)
  local in_file, in_err = io.open(source, "rb")
  if in_file == nil then
    error("Cannot open source file: " .. tostring(source) .. " (" .. tostring(in_err or "") .. ")")
  end
  local out_file, out_err = io.open(target, "wb")
  if out_file == nil then
    in_file:close()
    error("Cannot open target file: " .. tostring(target) .. " (" .. tostring(out_err or "") .. ")")
  end
  while true do
    local chunk = in_file:read(65536)
    if chunk == nil then
      break
    end
    out_file:write(chunk)
  end
  in_file:close()
  out_file:close()
  return true
end

local function _copy_entry_recursive(source, target)
  if _path_is_dir(source) then
    _ensure_dir(target)
    for _, entry in ipairs(_list_entries(source)) do
      _copy_entry_recursive(_join_path(source, entry.name), _join_path(target, entry.name))
    end
  else
    _copy_file_bytes(source, target)
  end
end

-- 目录镜像:先删目标再整体拷贝。跨文件系统(/mnt/c 与 ext4)时逐文件复制,
-- 可观察结果与历史镜像语义一致(目标侧陈旧文件消失,源侧隐藏项与空目录保留)。
function M.copy_directory_tree(source_dir, target_dir)
  if not _path_is_dir(source_dir) then
    error("Source directory does not exist: " .. tostring(source_dir))
  end
  M.reset_directory(target_dir)
  for _, entry in ipairs(_list_entries(source_dir)) do
    _copy_entry_recursive(_join_path(source_dir, entry.name), _join_path(target_dir, entry.name))
  end
end

function M.copy_file_with_parent_dir(source_path, target_path)
  local target_parent = _normalize_path(target_path):match("^(.*)/[^/]+$")
  if not _is_blank(target_parent) then
    _ensure_dir(target_parent)
  end
  return _copy_file_bytes(source_path, target_path)
end

function M.remove_nested_paths(root_dir, relative_paths)
  for _, relative_path in ipairs(relative_paths or {}) do
    local target = _join_path(root_dir, relative_path)
    if _path_exists(target) then
      _remove_path(target)
    end
  end
end

-- 统计函数。

-- #527:行首块注释(--[[ / --[==[ 等长括号形式)的内部行不是有效代码——
-- 每个 src 文件尾部的 mutate4lua manifest 即此形态,朴素口径曾虚高约 40%。
-- 行内开口(代码行尾的 --[[@as T]] 之类)不做状态跟踪:同仓库内该类注解
-- 均同行闭合,不影响口径。
function M.get_effective_lua_line_count_for_file(path_text)
  if not _path_is_file(path_text) then
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
    local trimmed = _trim(text)
    local _, open_end, equals = trimmed:find("^%-%-%[(=*)%[")
    if open_end ~= nil then
      block_close = "]" .. equals .. "]"
      local _, inline_close_end = trimmed:find(block_close, open_end + 1, true)
      if inline_close_end ~= nil then
        trimmed = _trim(trimmed:sub(inline_close_end + 1))
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
  if not _path_is_dir(path_text) then
    return 0
  end

  local total = 0
  for _, file_path in ipairs(_collect_lua_files(path_text, {})) do
    total = total + M.get_effective_lua_line_count_for_file(file_path)
  end
  return total
end

function M.get_lua_file_count(path_text)
  if not _path_exists(path_text) then
    return 0
  end
  if _path_is_file(path_text) then
    return 1
  end
  return #_collect_lua_files(path_text, {})
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

-- 主流程(历史坐标 deploy.ps1 #318-373,已随 #384 删除):顺序与输出逐行复刻。
local function main()
  local project_root = M.resolve_project_root()
  local resolved_platform = M.resolve_platform_name()
  local target_source = M.resolve_default_target_path(resolved_platform)
  local target_path = M.resolve_normalized_path(target_source)

  _ensure_dir(target_path)

  M.write_info("======================================")
  M.write_info("Starting project deployment")
  M.write_info("======================================")
  M.write_info("Project root: " .. tostring(project_root))
  M.write_info("Target path: " .. tostring(target_path))
  M.write_info("Target platform: " .. tostring(resolved_platform) .. " (written from WSL via /mnt/c)")
  M.write_info("")
  M.write_info("--------------------------------------")
  M.write_info("Deploy target: " .. tostring(target_path))
  M.write_info("--------------------------------------")
  for _, line in ipairs(M.format_uncommitted_notice(M.list_uncommitted_payload(project_root))) do
    M.write_info(line)
  end

  M.copy_directory_tree(_join_path(project_root, "src"), _join_path(target_path, "src"))
  M.copy_file_with_parent_dir(_join_path(project_root, "main.lua"), _join_path(target_path, "main.lua"))
  M.copy_file_with_parent_dir(
    _join_path(project_root, "Data/UIManagerNodes.lua"),
    _join_path(target_path, "Data/UIManagerNodes.lua")
  )
  M.copy_file_with_parent_dir(
    _join_path(project_root, "Data/Prefab.lua"),
    _join_path(target_path, "Data/Prefab.lua")
  )

  -- 统计读本地源侧:拷贝是 as-is,文件与有效行数量等价。
  local total_files =
    M.get_lua_file_count(_join_path(project_root, "src"))
    + M.get_lua_file_count(_join_path(project_root, "main.lua"))
    + M.get_lua_file_count(_join_path(project_root, "Data/UIManagerNodes.lua"))
    + M.get_lua_file_count(_join_path(project_root, "Data/Prefab.lua"))
  local total_effective_line_count =
    M.get_effective_lua_line_count_for_dir(_join_path(project_root, "src"))
    + M.get_effective_lua_line_count_for_file(_join_path(project_root, "main.lua"))
    + M.get_effective_lua_line_count_for_file(_join_path(project_root, "Data/UIManagerNodes.lua"))
    + M.get_effective_lua_line_count_for_file(_join_path(project_root, "Data/Prefab.lua"))

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

if ... == "tools.packages.ops.deploy" or ... == "packages.ops.deploy" then
  return M
end

os.exit(run_cli())
