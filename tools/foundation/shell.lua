-- 纯命令行演算:拼 shell 命令串、把 os.execute 的返回收成 (成功, 退出码)。
-- 不起子进程、不碰文件系统——起进程的是 proc,落盘的是 fs。
--
-- 这条边界的意义是:命令拼装与退出码判定可以脱离进程单测,不需要真跑一条命令。
--
-- WSL Ubuntu 单平台(ADR 0073):引号按 POSIX sh 口径(单引号包裹,内部单引号
-- 写成 '\'');环境变量按 `NAME=value cmd` 前缀导出。
local number_utils = require("src.foundation.number")
local path_lib = require("foundation.path")

local shell = {}

-- os.execute 在 Lua 5.4 返回 (ok, kind, code),但历史实现也可能直接返回一个数字退出码。
-- 两种形态都收成 (成功, 退出码),调用方只面对一种。
function shell.exit_status(ok, _, code)
  if type(ok) == "number" then
    return ok == 0, ok
  end
  if ok == true and (code == nil or (number_utils.is_numeric(code) and code == 0)) then
    return true, code or 0
  end
  if number_utils.is_numeric(code) and code == 0 then
    return true, 0
  end
  return false, code or 1
end

function shell.shell_quote(value)
  local text = tostring(value or "")
  assert(not text:find("[\r\n%z]"), "Command arguments cannot contain NUL or newlines")
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

function shell.build_command(args)
  local parts = {}
  for _, value in ipairs(args or {}) do
    parts[#parts + 1] = shell.shell_quote(value)
  end
  return table.concat(parts, " ")
end

-- `NAME=value` 赋值前缀(#124):值经 POSIX 引号包裹,键限定为合法环境变量名。
-- proc 与 parallel_lanes 共用这一处,保证导出语义单一。
function shell.build_env_assignment(name, value)
  local key = tostring(name or "")
  assert(key:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil, "Invalid environment variable name: " .. key)
  local text = tostring(value or "")
  assert(not text:find("[\r\n%z]"), "Environment values cannot contain NUL or newlines")
  return key .. "=" .. shell.shell_quote(text)
end

-- 环境变量表 → 赋值前缀序列(空格分隔,无尾随空格);nil/空表返回 ""。
function shell.build_env_lines(env)
  local parts = {}
  for key, value in pairs(env or {}) do
    parts[#parts + 1] = shell.build_env_assignment(key, value)
  end
  table.sort(parts)
  return table.concat(parts, " ")
end

function shell.wrap_command_with_cwd(command, cwd)
  local cwd_path = cwd and path_lib.normalize_path(cwd) or nil
  if cwd_path == nil or cwd_path == "" then
    return tostring(command or "")
  end
  return "cd " .. shell.shell_quote(cwd_path) .. " && " .. tostring(command or "")
end

return shell
