-- 原生 Windows 并行车道(ADR 0083):每条 lane 在自己的 launcher 脚本里跑,父进程
-- 等一次收全部结果。
--
-- 进程组收容已退场:原生 Windows 与 Git Bash 都没有 setsid。超时按「尽力收容」
-- 处理——看门狗到点先发布 124 timeout,再对直接子进程发一次 SIGKILL;lane 内自己
-- 派出的后台写手可能存活。原生进程树收容(cmd /c start + taskkill /T /F)与它的
-- 取证记为后续项,不在 #236 落地(ADR 0083)。
--
-- 为什么是「一个 supervisor 起全部 lane」而不是「逐 lane 起一次」:MSYS 的 bash
-- 在退出前会等完自己的后台作业(实测 bash -c 'sleep 5 &' 要等满 5 秒才返回),
-- 所以逐 lane 起一次 bash 会把 lane 串行化——后一条 lane 要等前一条收场才开工,
-- 分片并行就退化成了串行。把所有 lane 的启动放进同一个 bash 脚本(各自 & 起来)
-- 再等它们发布完成状态,并行才真正成立。
--
-- 与串行路径的契约逐字节一致:同一条命令串在串行里经 foundation.proc 执行,
-- 在这里经 lane 脚本里的 `sh` 执行;argv 表两处都由 shell.build_command 拼装,
-- 因此子进程看到的 arg[0] 与串行相同。
--
-- lane 经统一执行缝(foundation.shell.execute,内部 bash)起,不直接 os.execute:
-- 原生 Lua 的 os.execute 走 cmd.exe,既起不了 `sh ... &`,也读不懂 POSIX 引号。
local boundary = require("foundation.platform_boundary")
local env = require("foundation.env")
local fs = require("foundation.fs")
local path = require("foundation.path")
local proc = require("foundation.proc")
local shell = require("foundation.shell")
local M = {}

-- lane 脚本与启动器写进 lane 目录,由 sh 执行;不依赖任何外部编译器或宿主专用
-- 运行时(Windows 时代的 PowerShell/.NET Job Object 已退场)。
local function _status(entry)
  local text = fs.read_raw(entry.status)
  if not text then return nil end
  local code, reason = text:match("^(%d+) ([%w_]+)")
  return tonumber(code), reason
end

-- 尽力收容:按 status.pid 记的 pid 逐个 SIGKILL,失败就放过。
-- 不再有 `kill -- -<pgid>`:没有 setsid 就没有可复用的进程组,硬按组发信号会
-- 波及父进程自己所在的组。原生 Windows 上 MSYS 的 kill 只能停 MSYS 进程,
-- 直接子进程派出的原生进程可能存活——这正是「尽力」的含义。
local function _stop_lane(pid_file)
  local identity = fs.read_raw(pid_file)
  if identity == nil then return end
  for pid in tostring(identity):gmatch("%d+") do
    proc.run_command("kill -s KILL " .. pid .. " 2>/dev/null")
  end
end

-- 执行缝的返回形态兼容两种:os.execute 形态 (ok, "exit"|"unavailable", code) 与
-- (ok, code) 形态。判定一律折到 shell.exit_status,不在本模块另造一套。
-- 返回 nil 表示「执行缝不可用」(bash 起不来),false 表示命令没成功。
local function _started_ok(ok, kind, code)
  if kind == "unavailable" or (type(kind) == "number" and kind == boundary.UNAVAILABLE_EXIT_CODE) then
    return nil
  end
  return shell.exit_status(ok, kind, code)
end

-- 写一条 lane 的两个脚本:command.sh 是真正要跑的串,launcher.sh 是它的看门狗
-- 与完成状态发布者。不在这里启动——启动统一由 supervisor 脚本一次做完。
local function _write_lane_scripts(entry, timeout)
  local env_prefix = entry.env_lines ~= "" and (entry.env_lines .. " ") or ""
  local command_text = type(entry.cmd) == "table" and shell.build_command(entry.cmd) or tostring(entry.cmd)
  local command_ok, command_err = fs.write_file(entry.dir .. "/command.sh", table.concat({
    "#!/bin/sh",
    "cd " .. shell.shell_quote(entry.cwd or ".") .. " || exit 1",
    env_prefix .. command_text,
    "",
  }, "\n"))
  if not command_ok then return nil, command_err end

  -- 完成状态用「写临时文件再 mv」发布:等待方看到 status 文件即看到完整结论。
  -- status.pid 同时记 lane 所有者与真正命令进程的 pid(串行路径只暴露一个)。
  --
  -- 看门狗到点先发布 124 timeout、再 kill 直接子进程;launcher 在 wait 返回后
  -- 发现 status 已存在就不再覆盖——顺序是确定的,不会把 timeout 改写成 exit。
  local status = shell.shell_quote(entry.status)
  local status_done = shell.shell_quote(entry.status .. ".done")
  local launcher_ok, launcher_err = fs.write_file(entry.dir .. "/launcher.sh", table.concat({
    "#!/bin/sh",
    "sh " .. shell.shell_quote(entry.dir .. "/command.sh")
      .. " > " .. shell.shell_quote(entry.output) .. " 2>&1 &",
    "child=$!",
    "echo \"$$ $child\" > " .. shell.shell_quote(entry.status .. ".pid"),
    "(" .. "sleep " .. tostring(math.max(1, math.floor(timeout))) .. "; "
      .. "printf '%s %s\\n' 124 timeout > " .. status_done .. "; "
      .. "mv " .. status_done .. " " .. status .. "; "
      .. "kill -s KILL \"$child\" 2>/dev/null" .. ") >/dev/null 2>&1 &",
    "watchdog=$!",
    "wait \"$child\"",
    "code=$?",
    "kill -KILL \"$watchdog\" 2>/dev/null",
    "[ -e " .. status .. " ] && exit 0",
    "reason=exit",
    "[ \"$code\" -eq 127 ] && reason=launch_failed",
    "[ \"$code\" -eq 137 ] && reason=timeout",
    "printf '%s %s\\n' \"$code\" \"$reason\" > " .. status_done,
    "mv " .. status_done .. " " .. status,
    "",
  }, "\n"))
  if not launcher_ok then return nil, launcher_err end
  return true
end

-- supervisor:一次 bash 会话里把全部 lane 起起来(各自 &),再等它们发布完成状态。
--
-- 等待预算用「轮询次数」而不是墙钟:原生 Windows 上 `date +%s` 会解析到 Windows
-- 的 date.exe 并弹出「输入新日期」的交互提示(把无头运行挂死),所以脚本里不出现
-- date。每轮 0.05s,limit = 秒数 × 20。
local function _write_supervisor(entries, budget_seconds)
  local lines = { "#!/bin/sh" }
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = "sh " .. shell.shell_quote(entry.dir .. "/launcher.sh")
      .. " > " .. shell.shell_quote(entry.dir .. "/owner.log") .. " 2>&1 &"
  end
  lines[#lines + 1] = "limit=" .. tostring(math.max(1, math.floor(budget_seconds)) * 20)
  lines[#lines + 1] = "i=0"
  lines[#lines + 1] = "set --"
  for _, entry in ipairs(entries) do
    lines[#lines + 1] = "set -- \"$@\" " .. shell.shell_quote(entry.status)
  end
  lines[#lines + 1] = "while [ $# -gt 0 ]; do"
  lines[#lines + 1] = "  ready=1"
  lines[#lines + 1] = "  for s in \"$@\"; do"
  lines[#lines + 1] = "    [ -e \"$s\" ] || { ready=0; break; }"
  lines[#lines + 1] = "  done"
  lines[#lines + 1] = "  [ \"$ready\" -eq 1 ] && exit 0"
  lines[#lines + 1] = "  i=$((i + 1))"
  lines[#lines + 1] = "  [ \"$i\" -lt \"$limit\" ] || exit 124"
  lines[#lines + 1] = "  sleep 0.05"
  lines[#lines + 1] = "done"
  lines[#lines + 1] = "exit 0"
  lines[#lines + 1] = ""
  local supervisor = env.make_temp_path("parallel_supervisor", ".sh")
  local ok, err = fs.write_file(supervisor, table.concat(lines, "\n"))
  if not ok then return nil, err end
  return supervisor
end

function M.run(lanes, opts)
  opts = opts or {}
  local timeout = opts.timeout or 600
  local env_lines = shell.build_env_lines(opts.env)
  local cwd = env.current_dir()
  local entries = {}
  for _, lane in ipairs(lanes or {}) do
    local unique = env.make_temp_path("parallel_lane", "")
    local dir = opts.lane_dir and path.join_path(opts.lane_dir, unique:match("[^/]+$")) or unique
    local entry = { label = lane.label, cmd = lane.cmd, dir = dir, env_lines = env_lines, cwd = cwd }
    entry.output, entry.status = dir .. "/output.log", dir .. "/status.txt"
    entries[#entries + 1] = entry
    local prepared, prepare_err = fs.ensure_dir(dir)
    if prepared then
      local written, write_err = _write_lane_scripts(entry, timeout)
      if not written then entry.launch_error = tostring(write_err) end
    else
      entry.launch_error = tostring(prepare_err)
    end
  end

  -- 起得了的 lane 集合:准备失败的 lane 不进 supervisor(它没有 launcher 可起)。
  local runnable = {}
  for _, entry in ipairs(entries) do
    if entry.launch_error == nil then runnable[#runnable + 1] = entry end
  end

  local unavailable
  if #runnable > 0 then
    local supervisor, supervisor_err = _write_supervisor(runnable, timeout + 30)
    if supervisor == nil then
      unavailable = "failed to write lane supervisor: " .. tostring(supervisor_err)
    else
      local ok, kind, code = shell.execute("sh " .. shell.shell_quote(supervisor))
      fs.remove_path(supervisor)
      local started_ok = _started_ok(ok, kind, code)
      if started_ok == nil then
        unavailable = shell.bash_unavailable_message()
      elseif not started_ok then
        -- supervisor 自己没跑起来:不是 lane 的测试结论,是启动问题。
        unavailable = "failed to start lane supervisor (exit " .. tostring(code) .. ")"
      end
    end
  end

  local deadline_expired = unavailable == nil
  for _, entry in ipairs(runnable) do
    if _status(entry) == nil then deadline_expired = true end
  end

  local all_ok, results = #entries > 0, {}
  for _, entry in ipairs(entries) do
    local code, reason = _status(entry)
    local result = { label = entry.label, ok = false, exit_code = code, output = fs.read_raw(entry.output) or "" }
    local identity = fs.read_raw(entry.status .. ".pid") or ""
    result.owner_pid, result.child_pid = identity:match("(%d+)%s+(%d+)")
    if code == nil then
      -- 未发布完成状态:尽力收容,再落结论。
      _stop_lane(entry.status .. ".pid")
    end
    if unavailable ~= nil then
      -- 执行缝不可用 / supervisor 起不来:环境不可用(退 3),不是测试失败。
      result.reason, result.message = "unavailable", unavailable
      result.exit_code = boundary.UNAVAILABLE_EXIT_CODE
      result.output = unavailable
    elseif entry.launch_error then
      result.reason, result.message = "launch_failed", entry.launch_error
    elseif code == nil and deadline_expired then
      result.reason, result.message = "timeout", "Lane " .. tostring(entry.label) .. " exceeded " .. timeout .. "s"
      result.output = result.output .. (fs.read_raw(entry.dir .. "/owner.log") or "")
    elseif reason == "timeout" then
      result.reason, result.message = "timeout", "Lane " .. tostring(entry.label) .. " exceeded " .. timeout .. "s"
      result.output = result.output .. (fs.read_raw(entry.dir .. "/owner.log") or "")
    elseif code == nil then
      result.reason, result.message = "output_incomplete", "Owner did not publish completion state: " .. tostring(entry.label)
      result.artifact_dir = entry.dir
      result.output = result.output .. (fs.read_raw(entry.dir .. "/owner.log") or "")
    elseif reason ~= "exit" then
      result.reason, result.message = reason, "Lane " .. tostring(entry.label) .. " " .. reason .. ": " .. code
      result.output = result.output .. (fs.read_raw(entry.status .. ".error") or "")
    elseif code ~= 0 then
      result.reason, result.message = "exit", "Lane " .. tostring(entry.label) .. " exited " .. code
    elseif result.output == "" then
      result.reason, result.message = "output_incomplete", "Lane " .. tostring(entry.label) .. " exited 0 with empty output"
    else
      result.ok = true
    end
    if not result.artifact_dir then
      local cleaned, clean_err = fs.remove_path(entry.dir)
      if not cleaned then
        result.ok, result.artifact_dir = false, entry.dir
        result.message = tostring(result.message or "") .. "\n" .. tostring(clean_err)
      end
    end
    if not result.ok then
      all_ok = false
      if result.reason ~= "unavailable" and result.message
          and (result.output == "" or result.reason ~= "exit") then
        result.output = result.output .. (result.output == "" and "" or "\n") .. result.message .. "\n"
      end
    end
    results[#results + 1] = result
    if opts.stream ~= false and result.output ~= "" then
      io.write(result.output)
      if result.output:sub(-1) ~= "\n" then io.write("\n") end
    end
  end
  if opts.stream ~= false then io.flush() end
  return all_ok, results
end

return M
