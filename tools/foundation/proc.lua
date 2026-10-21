-- 子进程:跑一条命令并拿回 (ok, code, output)。
--
-- run_command 把 stdout/stderr 重定向到临时文件再读回来,所以本模块依赖 env(临时落点)
-- 与 fs(读回与清理)。反向不成立:fs 不认识子进程,这条单向依赖是分层的关键。
--
-- WSL Ubuntu 单平台(ADR 0073)。字符串按 POSIX sh 解释,数组是字面 argv
-- (经 shell 引号拼装后由 os.execute 交 /bin/sh -c 执行,argv 不会被二次解释)。环境变量以
-- `NAME=value` 前缀导出。不对输出换行或字节编码做隐式转换,非零退出码原样返回。
local text_lib = require("foundation.text")
local path_lib = require("foundation.path")
local shell_lib = require("foundation.shell")
local fs_lib = require("foundation.fs")
local env_lib = require("foundation.env")

local proc = {}

function proc.command_exists(name)
  local command_name = tostring(name or "")
  if command_name == "" then
    return false
  end

  local command = "command -v " .. shell_lib.shell_quote(command_name) .. " >/dev/null 2>&1"
  local ok, kind, code = os.execute(command)
  return shell_lib.exit_status(ok, kind, code)
end

function proc.run_command(command, options)
  local args = command
  if type(command) ~= "string" and (type(args) ~= "table" or #args == 0) then
    return {
      ok = false,
      code = 1,
      output = text_lib.bilingual("命令参数无效", "Invalid command arguments"),
    }
  end

  local output_path = env_lib.make_temp_path("command_output", ".log")
  local cwd_path = options and options.cwd and path_lib.normalize_path(options.cwd) or nil
  local stdin_path = options and options.stdin_path and path_lib.normalize_path(options.stdin_path) or nil

  local command_text = type(command) == "string" and command or shell_lib.build_command(args)

  -- options.env(#124):调用方解析一次的工具发现结果(如钉定的 Lua 5.4 路径)
  -- 以环境变量导出给子进程,子进程树自动继承,免去每个子进程重复探测。
  local env_prefix = ""
  if options and type(options.env) == "table" then
    local env_text = shell_lib.build_env_lines(options.env)
    if env_text ~= "" then
      env_prefix = env_text .. " "
    end
  end

  local redirected = env_prefix .. command_text
  if stdin_path ~= nil and stdin_path ~= "" then
    redirected = redirected .. " < " .. shell_lib.shell_quote(stdin_path)
  else
    redirected = redirected .. " < /dev/null"
  end
  redirected = redirected .. " > " .. shell_lib.shell_quote(output_path) .. " 2>&1"
  redirected = shell_lib.wrap_command_with_cwd(redirected, cwd_path)
  local ok, kind, code = os.execute(redirected)
  local success, exit_code = shell_lib.exit_status(ok, kind, code)
  local output = fs_lib.read_raw(output_path) or ""
  fs_lib.remove_path(output_path)
  return {
    ok = success,
    code = exit_code,
    output = output,
  }
end

-- 递归枚举 root 下指定扩展名的文件(含隐藏文件与隐藏目录),结果排序。
-- 返回绝对路径:`find` 的输出形态随传入根而变,调用方(分片、架构扫描、
-- 时长缓存)都按绝对路径对齐,这里一次收口。
function proc.collect_files(root, extension)
  local normalized_root = path_lib.normalize_path(root)
  local normalized_extension = tostring(extension or "")
  if normalized_extension ~= "" and normalized_extension:sub(1, 1) ~= "." then
    normalized_extension = "." .. normalized_extension
  end

  if not fs_lib.path_exists(normalized_root) then
    return nil, text_lib.bilingual_with_suffix("目录不存在: ", "Directory does not exist: ", root)
  end
  normalized_root = path_lib.resolve_path(env_lib.current_dir(), normalized_root)

  -- -print0:文件名可含空格、中文与换行;`find` 输出 NUL 分隔,这里按 NUL 切。
  -- 单条命令,退出码即 find 的结论(目录缺失时非零,不会把空扫描读成「没有文件」)。
  local command = "find " .. shell_lib.shell_quote(normalized_root) .. " -type f -print0 2>/dev/null"
  local result = proc.run_command(command)
  if not result.ok then
    return nil, text_lib.bilingual_with_suffix("收集文件失败: ", "Failed to collect files: ", root)
  end

  local files = {}
  for line in (result.output .. "\0"):gmatch("(.-)\0") do
    if line ~= "" and (normalized_extension == "" or line:sub(-#normalized_extension) == normalized_extension) then
      files[#files + 1] = path_lib.normalize_path(line)
    end
  end
  table.sort(files)
  return files
end

function proc.collect_lua_files(root)
  return proc.collect_files(root, ".lua")
end

function proc.open_path(path)
  local normalized = path_lib.normalize_path(path)
  local result = proc.run_command(env_lib.build_open_command(normalized))
  if not result.ok then
    return nil, text_lib.bilingual_with_suffix("打开路径失败: ", "Failed to open path: ", path)
  end
  return true
end

return proc
