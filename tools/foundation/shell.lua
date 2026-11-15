-- 命令行演算 + 全仓唯一执行缝:拼 shell 命令串、把执行结果收成 (成功, 退出码)、
-- 以及把命令真正交给 bash 跑。
--
-- 分工:命令**拼装**(shell_quote / build_command / build_env_lines / wrap_command_with_cwd)
-- 仍是纯演算,可以脱离进程单测;命令**执行**收在 shell.execute 一处,实现在
-- foundation/bash.lua(只依赖 os/io,故不与 env/fs 形成环)。
--
-- 原生 Windows 单平台(ADR 0083):引号按 POSIX sh 口径(单引号包裹,内部单引号
-- 写成 '\'');环境变量按 `NAME=value cmd` 前缀导出。原生 Lua 的 os.execute 在
-- Windows 走 cmd.exe,所以执行必须经 shell.execute,不得在别处直接 os.execute。
local number_utils = require("src.foundation.number")
local path_lib = require("foundation.path")
local bash_lib = require("foundation.bash")
local boundary = require("foundation.platform_boundary")

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

-- 执行缝的公开入口(ADR 0083):全仓唯一的命令执行入口,内部一律经 bash
-- (实现在 foundation/bash.lua,执行 + 读回输出只有那一份实现)。
--   默认返回 os.execute 形态 → (ok, "exit", code);找不到 bash 时 (nil, "unavailable", 3)。
--   options.capture = true 时返回 (output, ok, code),把 stdout+stderr 读回——需要读
--   子进程输出的调用方用它,不再各自拼 io.popen。找不到 bash 时 (nil, nil, 3)。
-- options.bash 可钉定解释器(测试用)。
function shell.execute(command, options)
  return bash_lib.execute(command, options)
end

-- bash 缺失时的不可用诊断(可机读状态词 + 安装指引),交各入口原样写 stderr 并退 3。
function shell.bash_unavailable_message(reason)
  local detail = reason or bash_lib.last_unavailable() or "no usable bash found"
  return boundary.unavailable_verdict("shell", " tool=bash step=discover", {
    "detail: " .. tostring(detail),
    "本仓工具链经 bash 执行命令(ADR 0083)。",
    "安装 Git for Windows 并把 bash 放进 PATH,或用 MONOPOLY_BASH 指向可执行的 bash:",
    "  https://gitforwindows.org/  (默认 C:/Program Files/Git/bin/bash.exe)",
  }).message
end

return shell