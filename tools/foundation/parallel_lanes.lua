-- WSL Ubuntu 并行车道(ADR 0073):每条 lane 在自己的会话/进程组里跑,父进程
-- 用一次阻塞等待收全部结果;超时按进程组收容,不只杀直接子进程。
--
-- 与串行路径的契约逐字节一致:同一条命令串在串行里经 foundation.proc 执行,
-- 在这里经 lane 脚本里的 `sh` 执行;argv 表两处都由 shell.build_command 拼装,
-- 因此子进程看到的 arg[0] 与串行相同(不再需要 Windows 时代的 where.exe 解析)。
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

-- 父进程一次性阻塞等待全部 lane 发布完成(#107 的 POSIX 形态):一个等待脚本
-- 轮询完成文件直到截止时间,不逐 lane 起进程、不依赖文件监视 API。
local function _wait_all(pending, seconds)
  if #pending == 0 then return true end
  local list = env.make_temp_path("parallel_wait", ".txt")
  local ok, write_err = fs.write_file(list, table.concat(pending, "\n") .. "\n")
  if not ok then return nil, write_err end
  local waiter = env.make_temp_path("parallel_wait", ".sh")
  fs.write_file(waiter, table.concat({
    "#!/bin/sh",
    "deadline=$(( $(date +%s) + " .. tostring(math.max(0, math.floor(seconds))) .. " ))",
    "while read -r status; do",
    "  [ -n \"$status\" ] || continue",
    "  while [ ! -e \"$status\" ]; do",
    "    [ \"$(date +%s)\" -lt \"$deadline\" ] || exit 124",
    "    sleep 0.05",
    "  done",
    "done < \"$1\"",
    "exit 0",
    "",
  }, "\n"))
  local result = proc.run_command({ "sh", waiter, list })
  fs.remove_path(list)
  fs.remove_path(waiter)
  return result.code == 0, result.code
end

-- 进程组收容:launcher 起在自己的进程组里,组 id 就是它自己的 pid。Linux 用
-- setsid 起新会话;macOS 没有 setsid 命令,改由 `set -m` 的作业控制给后台作业
-- 单独建组(组 id 同样是 launcher 的 pid)。
-- 收容只按组发一次 SIGKILL:launcher 自己也在组里,于是不会出现「收容后父进程
-- 继续写完成状态」的竞态;未发布完成状态即意味着整棵 lane 树被停掉。
local function _kill_group(pid_file)
  local identity = fs.read_raw(pid_file)
  local group = identity and identity:match("(%d+)")
  if group == nil then return end
  proc.run_command("kill -s KILL -- -" .. group .. " 2>/dev/null")
end

-- 计时由 lane 自己的看门狗执行(与命令同一进程组),父进程只阻塞等待完成状态:
-- 两处不各算一份超时,也就不会出现「父进程先到点、lane 却已正常发布」的分叉。
local function _launch(entry, timeout)
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
  -- 看门狗到点按组发 SIGKILL 并直接发布 124 timeout——kill 之后同一脚本不再有
  -- 机会被调度,所以结论必须由看门狗自己写。
  local launcher_ok, launcher_err = fs.write_file(entry.dir .. "/launcher.sh", table.concat({
    "#!/bin/sh",
    "(" .. "sleep " .. tostring(math.max(1, math.floor(timeout))) .. "; "
      .. "printf '%s %s\\n' 124 timeout > " .. shell.shell_quote(entry.status .. ".done") .. "; "
      .. "mv " .. shell.shell_quote(entry.status .. ".done") .. " " .. shell.shell_quote(entry.status) .. "; "
      .. "kill -s KILL -- -$$" .. ") >/dev/null 2>&1 &",
    "watchdog=$!",
    "sh " .. shell.shell_quote(entry.dir .. "/command.sh") .. " > " .. shell.shell_quote(entry.output) .. " 2>&1 &",
    "child=$!",
    "echo \"$$ $child\" > " .. shell.shell_quote(entry.status .. ".pid"),
    "wait \"$child\"",
    "code=$?",
    "kill -KILL \"$watchdog\" 2>/dev/null",
    "reason=exit",
    "[ \"$code\" -eq 127 ] && reason=launch_failed",
    "[ \"$code\" -eq 137 ] && reason=timeout",
    "printf '%s %s\\n' \"$code\" \"$reason\" > " .. shell.shell_quote(entry.status .. ".done"),
    "mv " .. shell.shell_quote(entry.status .. ".done") .. " " .. shell.shell_quote(entry.status),
    "",
  }, "\n"))
  if not launcher_ok then return nil, launcher_err end
  local launcher = shell.shell_quote(entry.dir .. "/launcher.sh")
  local owner_log = shell.shell_quote(entry.dir .. "/owner.log")
  local start_command
  if boundary.host_platform() == boundary.MACOS then
    start_command = "sh -c " .. shell.shell_quote("set -m; sh \"$1\" > \"$2\" 2>&1 &")
      .. " sh " .. launcher .. " " .. owner_log
  else
    start_command = "setsid sh " .. launcher .. " > " .. owner_log .. " 2>&1 &"
  end
  local started = os.execute(start_command)
  if not shell.exit_status(started) then return nil, "failed to start lane owner" end
  return true
end

function M.run(lanes, opts)
  opts = opts or {}
  local timeout = opts.timeout or 600
  local env_lines = shell.build_env_lines(opts.env)
  local cwd = env.current_dir()
  local entries = {}
  local started = os.time()
  for _, lane in ipairs(lanes or {}) do
    local unique = env.make_temp_path("parallel_lane", "")
    local dir = opts.lane_dir and path.join_path(opts.lane_dir, unique:match("[^/]+$")) or unique
    local entry = { label = lane.label, cmd = lane.cmd, dir = dir, env_lines = env_lines, cwd = cwd }
    entry.output, entry.status = dir .. "/output.log", dir .. "/status.txt"
    entries[#entries + 1] = entry
    local prepared, prepare_err = fs.ensure_dir(dir)
    if prepared then
      local launched, launch_err = _launch(entry, timeout)
      if not launched then entry.launch_error = tostring(launch_err) end
    else
      entry.launch_error = tostring(prepare_err)
    end
  end
  local pending = {}
  for _, entry in ipairs(entries) do
    if not entry.launch_error and _status(entry) == nil then pending[#pending + 1] = entry.status end
  end
  local deadline_expired = false
  if #pending > 0 then
    local waited, wait_code = _wait_all(pending, started + timeout + 30 - os.time())
    deadline_expired = waited ~= true and wait_code == 124
  end
  local all_ok, results = #entries > 0, {}
  for _, entry in ipairs(entries) do
    local code, reason = _status(entry)
    local result = { label = entry.label, ok = false, exit_code = code, output = fs.read_raw(entry.output) or "" }
    local identity = fs.read_raw(entry.status .. ".pid") or ""
    result.owner_pid, result.child_pid = identity:match("(%d+)%s+(%d+)")
    if code == nil then
      -- 未发布完成状态:按组收容整棵 lane 进程树,再落结论。
      _kill_group(entry.status .. ".pid")
    end
    if entry.launch_error then
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
      if result.message and (result.output == "" or result.reason ~= "exit") then
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
