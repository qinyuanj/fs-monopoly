-- tool_cli.lua —— 包内 cli.lua 进程内适配共享砖(#320 收尾 2,#322)。
--
-- 背景:各 tools/packages/<pkg>/cli.lua 的 in-process 直调曾分化为多种形态
-- (子进程兜底与退出码归一各自为政、pre-bootstrap 无兜底、双重 bootstrap;
-- 涉及的旧质量工具包已于 #94 退役)。本文件把四步收敛为单点:
--
--   require runner → 归一化退出码 → 子进程兜底
--
-- 各 cli.lua 的 main 只剩 --help 路由 + 一次 tool_cli.run 调用。调用方 env
-- 原样透传给 runner;默认值如何与调用方 env 合并由 runner 自理(#323),
-- cli adapter 不替 runner 合并。
--
-- `--help` / `-h` 的判定与 usage 输出也收在这里,所有包 cli 与顶层 tools/cli.lua
-- 共用,不再各自内联。帮助有两种位置语义,按子命令既有的退出码保留,不统一:
--   help_exit         任一位置命中:lint / verify / dry / deploy(ops) / sync-data /
--                     test_runner。这些子命令的其余参数是目标或开关,帮助可写在任意位置。
--   leading_help_exit 只看首参:clean / uml。首参之后的参数各自报用法错误
--                     (`clean foo --help` 退 2),统一成任一位置会改变退出码。
--   is_help_flag      其余按位置识别的场合直接用判定本身:gift-code(写注入的 stdout,
--                     且认 `new --help`)、probe / lint runner / encoding / spec_lane_args
--                     (在参数解析循环里置 help 标志)、顶层 tools/cli.lua(首参)。
--
-- 语义:
--   pcall(require, runner_module) 失败(缺上游工具、package.path 未装等)→
--   子进程兜底 `lua <runner_script> <args...>`,退出码透传(runner 脚本经
--   script_bootstrap 自举,不依赖调用方 package.path)。
--   加载成功 → runner.run(args, env) → 归一化:数字原样 / truthy→0 /
--   falsy→1。
-- runner.run 自身抛错不兜底——与 #320 前一致,错误冒泡给顶层 tools/cli.lua。
--
-- shell 拼装与退出码收成复用 foundation.shell(纯演算砖),不再各 cli 内联
-- _shell_quote。

local proc_lib = require("foundation.proc")

local tool_cli = {}

-- 归一化 run 返回值:数字退出码原样;布尔/真值语义 truthy→0、falsy→1。
-- 覆盖布尔与数字(dry/lint)两种 runner 契约。
function tool_cli.normalize_exit_code(result)
  if type(result) == "number" then
    return result
  end
  return result and 0 or 1
end

-- 子进程兜底:require runner 失败(缺上游工具、package.path 未装等)时改以
-- `<lua5.4> <runner_script>` 直跑脚本形态——runner 经 script_bootstrap 自举,不依赖
-- 调用方 package.path;退出码透传。非 "exit" 收场(signal 等)归 1。
-- 解释器身份取 foundation.lua54(入口统一 lua5.4,ADR 0073),不写死 PATH 上的 `lua`。
function tool_cli.forward_subprocess(runner_script, args)
  local parts = { require("foundation.lua54").lua54_bin(), runner_script }
  for _, value in ipairs(args or {}) do
    parts[#parts + 1] = value
  end
  local result = proc_lib.run_command(parts)
  io.write(result.output or "")
  return result.code or (result.ok and 0 or 1)
end

-- 统一入口。opts = { runner_module = "packages.<pkg>.runner",
--                     runner_script  = "tools/packages/<pkg>/runner.lua" }。
-- runner 模块须 return { env = <table 可选>, run = function(args, env) };
-- env 字段 adapter 自身不读,供契约套件等直接消费方取 runner 默认值。
-- env 实参原样透传给 runner.run;runner 默认值与调用方覆盖的合并由 runner
-- 自理,cli 不掺和(#323)。
function tool_cli.run(opts, args, env)
  local ok_load, runner = pcall(require, opts.runner_module)
  if not ok_load or type(runner) ~= "table" or type(runner.run) ~= "function" then
    return tool_cli.forward_subprocess(opts.runner_script, args)
  end
  return tool_cli.normalize_exit_code(runner.run(args or {}, env))
end

-- `--help` / `-h` 判定的唯一出处。
function tool_cli.is_help_flag(value)
  return value == "--help" or value == "-h"
end

-- 输出走 io.write(按调用时查表,dry / uml_quality 等测试替换全局 io.write)。
local function _write_usage(usage)
  io.write(usage())
  return 0
end

-- 任一参数是帮助开关时写出 usage() 并返回 0;否则返回 nil,调用方继续正常流程。
function tool_cli.help_exit(args, usage)
  for _, value in ipairs(args or {}) do
    if tool_cli.is_help_flag(value) then
      return _write_usage(usage)
    end
  end
  return nil
end

-- 首参是帮助开关时写出 usage() 并返回 0;否则返回 nil。
function tool_cli.leading_help_exit(args, usage)
  if tool_cli.is_help_flag((args or {})[1]) then
    return _write_usage(usage)
  end
  return nil
end

return tool_cli
