-- tool_cli.lua —— 包内 cli.lua 进程内适配共享砖(#320 收尾 2,#322)。
--
-- 背景:各 tools/packages/<pkg>/cli.lua 的 in-process 直调曾分化为多种形态
-- (子进程兜底与退出码归一各自为政、pre-bootstrap 无兜底、双重 bootstrap;
-- 涉及的旧质量工具包已于 #94 退役)。本文件把四步收敛为单点:
--
--   require runner → 归一化退出码 → 子进程兜底
--
-- 各 cli.lua 的 main 只剩 --help 路由 + 一次 tool_cli.run 调用。env merge 的
-- 唯一落点在 runner 侧(#323):runner 以自身 _env 为底经 tool_cli.merge_env
-- 合并调用方 env;cli adapter 只透传,不替 runner 合并——否则会出现
-- cli/runner 双侧各 merge 一遍的冗余。
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

-- env merge 唯一出处(#323):base 为底、overrides 覆盖(后者优先),nil 侧按
-- 空表计;不改动入参,返回新表。职责落点在 runner 侧——runner 用自己的 _env
-- 默认值做 base 合并调用方透传来的 env;cli adapter 不替 runner 合并(见 run)。
function tool_cli.merge_env(base, overrides)
  local merged = {}
  if type(base) == "table" then
    for key, value in pairs(base) do merged[key] = value end
  end
  if type(overrides) == "table" then
    for key, value in pairs(overrides) do merged[key] = value end
  end
  return merged
end

-- 统一入口。opts = { runner_module = "packages.<pkg>.runner",
--                     runner_script  = "tools/packages/<pkg>/runner.lua" }。
-- runner 模块须 return { env = <table 可选>, run = function(args, env) };
-- env 字段 adapter 自身不读,供契约套件等直接消费方取 runner 默认值。
-- env 实参原样透传给 runner.run;merge(runner 默认值 + 调用方覆盖)由
-- runner 侧经 tool_cli.merge_env 完成,cli 不掺和(#323 唯一落点)。
function tool_cli.run(opts, args, env)
  local ok_load, runner = pcall(require, opts.runner_module)
  if not ok_load or type(runner) ~= "table" or type(runner.run) ~= "function" then
    return tool_cli.forward_subprocess(opts.runner_script, args)
  end
  return tool_cli.normalize_exit_code(runner.run(args or {}, env))
end

return tool_cli
