-- 原生 Windows 并行车道(ADR 0083 第 6 条):每条 lane 在自己的 owner 脚本里跑,
-- 父进程用一次阻塞等待收全部结果。
--
-- 与串行路径的契约逐字节一致:同一条命令串在串行里经 foundation.proc 执行,
-- 在这里经 lane 脚本里的 `sh` 执行;argv 表两处都由 shell.build_command 拼装,
-- 因此子进程看到的 arg[0] 与串行相同。
--
-- 并行退场的前置条件已满足:setsid 在原生 Windows / MSYS 都没有,所以这里不建进程组,
-- 超时按 pid 停直接子进程(原生进程树收容记为后续取证项)。
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

-- 父进程一次性阻塞等待全部 lane 发布完成(#107 的形态):一个等待脚本
-- 轮询完成文件直到截止时间,不逐 lane 起进程、不依赖文件监视 API。
--
-- 截止时间不靠 `date +%s`:在原生 Windows 上 date 可能命中系统改日期交互命令
-- (会弹窗并阻塞),所以改用 sleep 逐次倒计时——等待脚本只需要"最多等多久"。
local function _wait_all(pending, seconds)
  if #pending == 0 then return true end
  local list = env.make_temp_path("parallel_wait", ".txt")
  local ok, write_err = fs.write_file(list, table.concat(pending, "\n") .. "\n")
  if not ok then return nil, write_err end
  local waiter = env.make_temp_path("parallel_wait", ".sh")
  local budget = math.max(0, math.floor(seconds))
  fs.write_file(waiter, table.concat({
    "#!/bin/sh",
    -- 每个待收 lane 最多等 budget 秒:一次 sleep 记一格,超时退 124。
    "remaining=" .. tostring(budget),
    "while read -r status; do",
    "  [ -n \"$status\" ] || continue",
    "  while [ ! -e \"$status\" ]; do",
    "    [ \"$remaining\" -gt 0 ] || exit 124",
    "    remaining=$(( remaining - 1 ))",
    "    sleep 1",
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

-- 收容:按 lane 自己的命令进程 pid 停它,不发信号给整棵进程组。
--
-- ADR 0083 第 6 条:原生 Windows / MSYS 都没有 setsid,进程组收容在保证面内不存在
-- (原生进程树收容 cmd /c start + taskkill /T /F /PID 记为后续取证项,不在本次落地)。
-- 所以 lane 的 owner 与命令进程同组,按组发信号会连父进程一起带走——改为按 pid 停
-- 直接子进程。status.pid 记着 "owner_pid child_pid",后者才是要停的那个。
local function _kill_lane(pid_file)
  local identity = fs.read_raw(pid_file)
  local child = identity and identity:match("%d+%s+(%d+)")
  if child == nil then return end
  proc.run_command("kill -s KILL " .. child .. " 2>/dev/null")
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
    -- 命令先起,拿到 pid;看门狗再起,超时按 pid 停它(ADR 0083 第 6 条:无进程组收容)。
    -- 子 shell 用 exec 把命令换成自己:记下的 pid 就是命令进程本身,超时才真停得住。
    "( cd " .. shell.shell_quote(entry.cwd or ".") .. " || exit 1; "
      .. (env_prefix ~= "" and ("export " .. env_prefix .. "; ") or "")
      .. "exec " .. command_text
      .. " ) > " .. shell.shell_quote(entry.output) .. " 2>&1 &",
    "child=$!",
    "echo \"$$ $child\" > " .. shell.shell_quote(entry.status .. ".pid"),
    -- 看门狗:先停命令,再发布超时结论。顺序不能反——先发布会让父进程在命令
    -- 还活着时就收走 lane,被停掉的命令仍可能完成它的迟到写入。
    "(" .. "sleep " .. tostring(math.max(1, math.floor(timeout))) .. "; "
      .. "kill -s KILL " .. "$child" .. " 2>/dev/null; "
      .. "printf '%s %s\\n' 124 timeout > " .. shell.shell_quote(entry.status .. ".done") .. "; "
      .. "mv " .. shell.shell_quote(entry.status .. ".done") .. " " .. shell.shell_quote(entry.status) .. ") >/dev/null 2>&1 &",
    "watchdog=$!",
    "wait \"$child\"",
    "code=$?",
    "kill -KILL \"$watchdog\" 2>/dev/null",
    "reason=exit",
    "[ \"$code\" -eq 127 ] && reason=launch_failed",
    "[ \"$code\" -eq 137 ] && reason=timeout",
    -- 看门狗已发布超时结论时不再覆盖它:发布者只有一个,结论不因谁先写而分叉。
    "if [ ! -e " .. shell.shell_quote(entry.status) .. " ]; then",
    "  printf '%s %s\\n' \"$code\" \"$reason\" > " .. shell.shell_quote(entry.status .. ".done"),
    "  mv " .. shell.shell_quote(entry.status .. ".done") .. " " .. shell.shell_quote(entry.status),
    "fi",
    "",
  }, "\n"))
  if not launcher_ok then return nil, launcher_err end
  local launcher = shell.shell_quote(entry.dir .. "/launcher.sh")
  local owner_log = shell.shell_quote(entry.dir .. "/owner.log")
  -- 不再 setsid(ADR 0083 第 6 条:原生 Windows / MSYS 都没有它):owner 直接后台起。
  -- 收容按 pid 停直接子进程,不做进程组收容。
  local start_command = "sh " .. launcher .. " > " .. owner_log .. " 2>&1 &"
  local started = shell.execute(start_command)
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
      -- 未发布完成状态:停掉 lane 的直接子进程,再落结论。
      _kill_lane(entry.status .. ".pid")
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
