-- packages/probe/cli.lua —— probe 子命令:试玩态探针(契约见 usage() 与 test/)。
--
-- 统一接口形态(#300 决议):
--   M.main(args, env) -> 退出码(0 有命中 / 1 失败或超时无命中 / 2 用法错误 / 3 editor-cli 不可用)
--   M.usage()         -> 完整 usage 文本(包内单一真源)
--
-- 流程:解析 editor-cli.exe(经 cmd.exe 取 %USERPROFILE% 再 wslpath 换算,与 deploy 同一
-- 解析函数)→ status 确认 in_game_runtime True → 在用户脚本前注入 probe(...) 并包进
-- EditorAPI.game_execute([==[ ... ]==]),写临时文件经 `exec --file` 执行(多行脚本不过
-- shell 引号)→ 轮询 `log grep <标记>` 直到命中或超时,命中行打到 stdout。
-- 不调用 play start / stop。
--
-- env 注入面(测试用;缺省即真实环境):
--   run(argv|string, { cwd = ... }) -> { ok, code, output }   子进程执行器
--   command_exists(name) -> bool、resolve_home() -> Windows 家目录的 WSL 路径或 ""
--   file_exists(path)、read_file(path) -> string|nil、write_file(path, text) -> bool、remove_file(path)
--   now() -> 秒(标记用)、clock() -> 秒(超时用)、sleep(秒)、random_hex() -> string
--   stdout / stderr(带 :write 的对象)
local M = {}

local boundary = require("foundation.platform_boundary")
local script = require("packages.probe.script")
local tool_cli = require("foundation.tool_cli")

local DEFAULT_TIMEOUT = 10
local POLL_INTERVAL = 0.5
-- 首次命中后再等一拍重读,收齐同一次 game_execute 里稍后落盘的 probe 行。
local SETTLE_DELAY = 0.5
local CLI_SUBDIR = ".eggitor/cli"
local EXE_NAME = "editor-cli.exe"

function M.usage()
  return table.concat({
    "用法: lua5.4 tools/cli.lua probe <lua文件> [--timeout <秒,默认 " .. DEFAULT_TIMEOUT .. ">]",
    "",
    "在试玩态(in_game_runtime True)的游戏 Lua 环境里执行 <lua文件>,取回其 probe(...) 输出。",
    "  脚本前会注入 local function probe(...) print('<标记>', ...) end;标记形如 DEBUG-PROBE-<时间戳>-<随机>。",
    "  脚本经 EditorAPI.game_execute 执行(不回传值),之后轮询 editor-cli log grep <标记>,",
    "  只把命中行(去掉行号前缀)打印到 stdout。",
    "  --timeout  等待命中的秒数,正数,默认 " .. DEFAULT_TIMEOUT,
    "",
    "editor-cli 路径: %USERPROFILE%/" .. CLI_SUBDIR .. "/" .. EXE_NAME .. "(经 cmd.exe + wslpath 解析)。",
    "不会开启或结束试玩;不在试玩态时退 1,请先在编辑器里开启试玩。",
    "退出码:0 有命中 / 1 失败或超时无命中 / 2 用法错误 / 3 editor-cli 不可用(status=unavailable tool=editor-cli step=<步>)",
    "",
  }, "\n") .. "\n"
end

-- 默认依赖 ----------------------------------------------------------------

local function _default_run(command, options)
  return require("foundation.proc").run_command(command, options)
end

local function _default_command_exists(name)
  return require("foundation.proc").command_exists(name)
end

local function _default_file_exists(path)
  local handle = io.open(path, "rb")
  if handle == nil then
    return false
  end
  handle:close()
  return true
end

local function _default_read_file(path)
  local handle = io.open(path, "rb")
  if handle == nil then
    return nil
  end
  local text = handle:read("a")
  handle:close()
  return text
end

local function _default_write_file(path, text)
  local handle = io.open(path, "wb")
  if handle == nil then
    return false
  end
  local ok = handle:write(text) ~= nil
  handle:close()
  return ok
end

local function _default_remove_file(path)
  os.remove(path)
end

local function _default_sleep(seconds)
  os.execute("sleep " .. string.format("%.3f", seconds))
end

local function _default_clock()
  -- os.time 是整秒;超时判定按墙钟,秒级精度足够。
  return os.time()
end

local function _default_random_hex()
  local handle = io.open("/dev/urandom", "rb")
  local bytes = handle and handle:read(4) or nil
  if handle then
    handle:close()
  end
  if type(bytes) ~= "string" or #bytes ~= 4 then
    math.randomseed(os.time(), os.clock() * 1000000)
    return string.format("%08x", math.random(0, 0x7fffffff))
  end
  return (bytes:gsub(".", function(c)
    return string.format("%02x", c:byte())
  end))
end

-- 外层子壳:deploy 的命令自带 2>/dev/null,proc 在末尾追加 `> out 2>&1` 会覆盖它;
-- 包一层 ( ... ) 让内部重定向先生效,cmd.exe 的 UNC 警告不混进 %USERPROFILE% 输出。
local function _resolve_home_with(run)
  local deploy = require("packages.ops.deploy")
  return deploy.resolve_windows_home_dir(function(command)
    local result = run("(" .. command .. ")")
    return result and result.output or ""
  end)
end

local function _deps(env)
  env = env or {}
  local run = env.run or _default_run
  return {
    run = run,
    command_exists = env.command_exists or _default_command_exists,
    resolve_home = env.resolve_home or function()
      return _resolve_home_with(run)
    end,
    file_exists = env.file_exists or _default_file_exists,
    read_file = env.read_file or _default_read_file,
    write_file = env.write_file or _default_write_file,
    remove_file = env.remove_file or _default_remove_file,
    now = env.now or os.time,
    clock = env.clock or _default_clock,
    sleep = env.sleep or _default_sleep,
    random_hex = env.random_hex or _default_random_hex,
    stdout = env.stdout or io.stdout,
    stderr = env.stderr or io.stderr,
  }
end

-- 参数 --------------------------------------------------------------------

local function _parse_args(args)
  local opts = { timeout = DEFAULT_TIMEOUT }
  local index = 1
  while index <= #args do
    local value = args[index]
    if tool_cli.is_help_flag(value) then
      return { help = true }
    elseif value == "--timeout" then
      local text = args[index + 1]
      local seconds = text and text:match("^%d+%.?%d*$") and tonumber(text) or nil
      if seconds == nil or seconds <= 0 then
        return nil, "--timeout 需要正数秒: " .. tostring(text)
      end
      opts.timeout = seconds
      index = index + 1
    elseif value:sub(1, 2) == "--" then
      return nil, "未知选项: " .. value
    elseif opts.file ~= nil then
      return nil, "只接受一个 lua 文件,多余参数: " .. value
    else
      opts.file = value
    end
    index = index + 1
  end
  if opts.file == nil then
    return nil, "缺少 <lua文件>"
  end
  return opts
end

-- 流程 --------------------------------------------------------------------

local function _unavailable(deps, step, lines)
  local verdict = boundary.unavailable_verdict("probe", " tool=editor-cli step=" .. step, lines)
  deps.stderr:write(verdict.message)
  return verdict.exit_code
end

local function _fail(deps, message, detail)
  deps.stderr:write("[probe] ERROR " .. message .. "\n")
  if detail ~= nil and detail ~= "" then
    deps.stderr:write(detail)
    if detail:sub(-1) ~= "\n" then
      deps.stderr:write("\n")
    end
  end
  return 1
end

-- 返回 (editor-cli 所在目录, nil) 或 (nil, 退出码)。
local function _locate_cli(deps)
  local missing = {}
  for _, name in ipairs({ "cmd.exe", "wslpath" }) do
    if not deps.command_exists(name) then
      missing[#missing + 1] = name
    end
  end
  if #missing > 0 then
    return nil, _unavailable(deps, "interop", {
      "定位 editor-cli 需要 WSL 互操作面:缺 " .. table.concat(missing, ", ") .. "。",
      "处理: 在 WSL Ubuntu 中运行,并确认 /mnt/c 已挂载(cmd.exe 与 wslpath 可见)。",
    })
  end
  local home = deps.resolve_home()
  if home == nil or home == "" then
    return nil, _unavailable(deps, "userprofile", {
      "无法经 cmd.exe 解析 Windows %USERPROFILE%。",
      "处理: 确认 /mnt/c 已挂载且 cmd.exe 可正常执行,再重跑。",
    })
  end
  local dir = home:gsub("/+$", "") .. "/" .. CLI_SUBDIR
  if not deps.file_exists(dir .. "/" .. EXE_NAME) then
    return nil, _unavailable(deps, "executable", {
      "找不到 " .. dir .. "/" .. EXE_NAME .. "。",
      "处理: 在编辑器里启用 editor-cli(或 env-res update editor_cli_win)后重跑。",
    })
  end
  return dir
end

local function _grep(deps, cli_dir, marker)
  local result = deps.run({ "./" .. EXE_NAME, "log", "grep", marker,
    "--context", "0", "--max-matches", "1000", "--case-sensitive" }, { cwd = cli_dir })
  return result or { ok = false, code = 1, output = "" }
end

local function _poll(deps, cli_dir, marker, timeout)
  local deadline = deps.clock() + timeout
  local last_failure
  while true do
    local result = _grep(deps, cli_dir, marker)
    local hits = result.ok and script.parse_hits(result.output) or {}
    if not result.ok then
      last_failure = result.output
    end
    if #hits > 0 then
      deps.sleep(SETTLE_DELAY)
      local again = _grep(deps, cli_dir, marker)
      local more = again.ok and script.parse_hits(again.output) or {}
      return #more > #hits and more or hits
    end
    if deps.clock() >= deadline then
      return nil, last_failure
    end
    deps.sleep(POLL_INTERVAL)
  end
end

function M.main(args, env)
  local deps = _deps(env)
  local opts, err = _parse_args(args or {})
  if opts == nil then
    deps.stderr:write("[probe] " .. err .. "\n\n" .. M.usage())
    return 2
  end
  if opts.help then
    deps.stdout:write(M.usage())
    return 0
  end

  local source = deps.read_file(opts.file)
  if source == nil then
    return _fail(deps, "读不到 lua 文件: " .. opts.file)
  end

  local cli_dir, code = _locate_cli(deps)
  if cli_dir == nil then
    return code
  end

  local status = deps.run({ "./" .. EXE_NAME, "status" }, { cwd = cli_dir }) or {}
  if not status.ok then
    return _unavailable(deps, "status", {
      "editor-cli status 失败(退出码 " .. tostring(status.code) .. "),编辑器可能未启动或未开 editor-cli:",
      (tostring(status.output or ""):gsub("%s+$", "")),
    })
  end
  if not script.in_game_runtime(status.output) then
    return _fail(deps, "当前不在试玩态(in_game_runtime 非 True)。请先在编辑器里开启试玩,"
      .. "等 status 显示 in_game_runtime True 后重跑;probe 不会代为开启试玩。")
  end

  local marker = script.make_marker(deps.now(), deps.random_hex())
  -- 临时脚本放在 editor-cli 目录里,原生 Windows 可执行按相对路径读取,无需路径换算。
  local file_name = ".probe-" .. marker .. ".lua"
  local file_path = cli_dir .. "/" .. file_name
  if not deps.write_file(file_path, script.wrap(source, marker)) then
    return _fail(deps, "写不出临时脚本: " .. file_path)
  end
  local exec = deps.run({ "./" .. EXE_NAME, "exec", "--file", file_name }, { cwd = cli_dir }) or {}
  deps.remove_file(file_path)
  if not exec.ok then
    return _fail(deps, "editor-cli exec 失败(退出码 " .. tostring(exec.code) .. "):", exec.output)
  end

  local hits, last_failure = _poll(deps, cli_dir, marker, opts.timeout)
  if hits == nil then
    return _fail(deps, string.format("%s 秒内 log grep %s 无命中(脚本未调 probe,或游戏内报错;"
      .. "用 editor-cli log grep 查看报错)。", tostring(opts.timeout), marker), last_failure)
  end
  for _, line in ipairs(hits) do
    deps.stdout:write(line .. "\n")
  end
  return 0
end

return M
