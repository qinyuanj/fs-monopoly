-- bash.lua —— 全仓唯一的命令执行缝(ADR 0083 / #235)。
--
-- 原生 Lua 的 os.execute 在 Windows 上一定经 cmd.exe:它不认 POSIX 单引号、不认
-- NAME=value 前缀,还会把 %PATH% 这类文本展开成真实环境变量、把 & | < > ^ ( ) 当元字符。
-- 既有命令串全是 POSIX 口径(fs 的 mkdir -p / rm -rf / cp -R,proc 的 command -v /
-- find -print0 / 重定向),原样交给 cmd.exe 必失败,所以命令一律交 bash 执行。
--
-- 执行形态是**脚本文件**:每次执行把命令文本原样写进临时 .sh,再用
-- 双引号包住 bash 路径、空格、脚本路径、再包一层双引号的整行运行。整行再包一层
-- 双引号是因为 cmd.exe 会剥掉最外层一对引号,剩下的 "bash" "script" 才是 bash 要的;
-- 不包外层的裸形态在路径含空格时直接炸(C:/Program is not recognized)。
-- 不采用内联 -c 的实测理由:cmd.exe 会在命令行上展开 %...%,含 % 的命令串经 -c 会被
-- 静默改写;脚本文件形态实测把 a"b&c|d<e>f^g%PATH%h(i)j!k 逐字节送达 bash
-- (#235 验收:既有命令串语义不变)。
--
-- 本模块刻意**只依赖 os/io**,不 require 任何 foundation 模块:执行缝在依赖图最底层,
-- fs / proc / parallel_lanes / env 都依赖它。若它反向依赖 env(临时目录)或 fs(落盘),
-- 就会形成 shell→env→fs→shell 的环。临时目录因此在这里自取自用(读原生进程的
-- TEMP/TMP,缺省 C:/Windows/Temp),环境变量也是直接 os.getenv。
--
-- bash 发现顺序(ADR 0083 第 2 条):MONOPOLY_BASH / BASH 环境变量 → PATH 上的 bash
-- → 常见 Git for Windows 安装路径。每个候选都要**真跑一个探针脚本**通过才采纳:
-- 本机的 BASH 可能是 bash 兼容壳,只看"文件存在"会把不工作的解释器当成 bash。
-- 全找不到就是环境不可用(退 3 + 安装指引),不是测试失败。
local bash = {}

bash.UNAVAILABLE_EXIT_CODE = 3

-- 找不到 bash 时的可机读原因(渲染成 status=unavailable 由调用方负责)。
bash.UNAVAILABLE_REASON = "bash"

local SEPARATOR = string.char(34)
local _SCRIPT_PREFIX = "eggy_exec_"
local _counter = 0
local _resolved -- 发现结果:成功是路径字符串,失败是 false,未探测是 nil
local _last_unavailable

-- 内部路径口径:D:/… 正斜杠。TEMP/TMP 来自原生 Lua 进程,不读 bash 继承来的值
-- (Git Bash 会把 TMP 覆盖成 /tmp)。
function bash.system_tmp_dir()
  local value = os.getenv("TEMP")
  if value == nil or value == "" then
    value = os.getenv("TMP")
  end
  if value == nil or value == "" then
    value = "C:/Windows/Temp"
  end
  return (tostring(value):gsub("\\", "/"):gsub("/+$", ""))
end

local function _exists(file)
  if file == nil or file == "" then
    return false
  end
  local handle = io.open(file, "rb")
  if handle ~= nil then
    handle:close()
    return true
  end
  return false
end

-- WSL 的 C:/Windows/System32/bash.exe 也是一个 bash,但它跑不了原生 Windows 路径,
-- 发现到它等于把工具链扔进另一个操作系统(where bash 会把它列出来)。
local function _is_wsl_bash(file)
  return _exists(file) and tostring(file):lower():find("/system32/bash", 1, true) ~= nil
end

local function _path_entries()
  local entries, seen = {}, {}
  local raw = os.getenv("PATH") or ""
  for entry in tostring(raw):gmatch("[^;]+") do
    local trimmed = entry:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/"):gsub("/+$", "")
    if trimmed ~= "" and seen[trimmed] == nil then
      seen[trimmed] = true
      entries[#entries + 1] = trimmed
    end
  end
  return entries
end

local function _env_candidate(name)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return nil
  end
  return (tostring(value):gsub("\\", "/"))
end

-- 候选来源按 ADR 0083 的顺序排列,每一项是 { source = ..., path = ... }。
function bash.candidates()
  local list = {}
  for _, name in ipairs({ "MONOPOLY_BASH", "BASH" }) do
    local value = _env_candidate(name)
    if value ~= nil then
      list[#list + 1] = { source = name, path = value }
    end
  end
  for _, dir in ipairs(_path_entries()) do
    for _, name in ipairs({ "bash.exe", "bash" }) do
      local candidate = dir .. "/" .. name
      if _exists(candidate) and not _is_wsl_bash(candidate) then
        list[#list + 1] = { source = "PATH", path = candidate }
      end
    end
  end
  for _, dir in ipairs({
    "C:/Program Files/Git/bin",
    "C:/Program Files/Git/usr/bin",
    "C:/Program Files (x86)/Git/bin",
    "C:/Program Files (x86)/Git/usr/bin",
  }) do
    for _, name in ipairs({ "bash.exe", "bash" }) do
      local candidate = dir .. "/" .. name
      if _exists(candidate) then
        list[#list + 1] = { source = "git-install", path = candidate }
      end
    end
  end
  return list
end

local function _temp_script_path()
  _counter = _counter + 1
  local token = tostring({}):gsub("[^%w]+", "")
  if token == "" then token = "ptr" end
  return table.concat({
    bash.system_tmp_dir(),
    "/",
    _SCRIPT_PREFIX,
    tostring(os.time()),
    "_",
    tostring(_counter),
    "_",
    token,
    ".sh",
  })
end

-- cmd 行:外层双引号 + "bash" + 空格 + "script",再整体包一层双引号。
local function _command_line(executable, script)
  return SEPARATOR .. SEPARATOR .. executable .. SEPARATOR
    .. " " .. SEPARATOR .. script .. SEPARATOR .. SEPARATOR
end

-- 把一个候选真跑一次:探针脚本既写标记文件又用非零退出码收场。
-- 只有"脚本被执行了 + 退出码原样传出"同时成立,才算这个候选是能用的 bash。
local function _probe(executable)
  local marker = _temp_script_path() .. ".marker"
  local script = _temp_script_path()
  local handle = io.open(script, "wb")
  if handle == nil then
    return false
  end
  handle:write("printf '%s' 'bash-ok' > '" .. marker .. "'\n")
  handle:write("exit 7\n")
  handle:close()

  local ok, _, code = os.execute(_command_line(executable, script))
  os.remove(script)

  local readable = io.open(marker, "rb")
  local produced = false
  if readable ~= nil then
    produced = readable:read("*a") == "bash-ok"
    readable:close()
  end
  os.remove(marker)

  return code == 7 and produced and ok ~= true
end

-- 发现 bash。返回 (路径, nil) 或 (nil, 原因)。
-- override 由调用方显式钉定(测试与 MONOPOLY_BASH 同一条路径),同样要过探针。
function bash.discover(override)
  if override ~= nil then
    local pinned = tostring(override):gsub("\\", "/")
    if _probe(pinned) then
      return pinned, nil
    end
    return nil, "pinned bash does not execute scripts: " .. pinned
  end
  if _resolved == nil then
    for _, candidate in ipairs(bash.candidates()) do
      if _probe(candidate.path) then
        _resolved = candidate.path
        break
      end
    end
    if _resolved == nil then
      _resolved = false
    end
  end
  if _resolved == false then
    return nil, "no usable bash found"
  end
  return _resolved, nil
end

-- 发现结果缓存的外部重置(测试与子进程环境切换用)。
function bash.reset()
  _resolved = nil
  _last_unavailable = nil
end

-- 最近一次不可用的具体原因,供诊断文本使用。
function bash.last_unavailable()
  return _last_unavailable
end

-- 唯一执行入口:命令文本写进临时脚本,交 bash 执行;退出码原样返回。
-- 返回 (ok, "exit", code),与 os.execute 的 Lua 5.4 形态一致,调用方判定逻辑不变。
-- 找不到 bash 时返回 (nil, "unavailable", 3) 并记下原因。
function bash.execute(command, options)
  options = options or {}
  local executable, reason = bash.discover(options.bash)
  if executable == nil then
    _last_unavailable = reason
    return nil, "unavailable", bash.UNAVAILABLE_EXIT_CODE
  end

  local script = _temp_script_path()
  local handle = io.open(script, "wb")
  if handle == nil then
    _last_unavailable = "cannot write command script under " .. bash.system_tmp_dir()
    return nil, "unavailable", bash.UNAVAILABLE_EXIT_CODE
  end
  local body = tostring(command or "")
  handle:write(body)
  if body:sub(-1) ~= "\n" then
    handle:write("\n")
  end
  handle:close()

  local ok, kind, code = os.execute(_command_line(executable, script))
  os.remove(script)
  return ok, kind, code
end

-- 带输出捕获的执行:同一脚本文件缝,改走 io.popen 把 stdout 读回来。
-- 返回 (output, ok, code);bash 缺失返回 (nil, nil, "unavailable")。
-- 需要读子进程输出的调用方(lua_env 的 luarocks 探测)用它,不再各自拼 popen。
function bash.capture(command, options)
  options = options or {}
  local executable, reason = bash.discover(options.bash)
  if executable == nil then
    _last_unavailable = reason
    return nil, nil, "unavailable"
  end

  local script = _temp_script_path()
  local handle = io.open(script, "wb")
  if handle == nil then
    _last_unavailable = "cannot write command script under " .. bash.system_tmp_dir()
    return nil, nil, "unavailable"
  end
  local body = tostring(command or "")
  handle:write(body)
  if body:sub(-1) ~= "\n" then
    handle:write("\n")
  end
  handle:close()

  local pipe = io.popen(_command_line(executable, script) .. " 2>&1")
  if pipe == nil then
    os.remove(script)
    _last_unavailable = "cannot start bash for output capture"
    return nil, nil, "unavailable"
  end
  local output = pipe:read("*a") or ""
  local ok, _, code = pipe:close()
  -- 脚本必须在子进程读完(close 等到收场)之后再删:popen 返回时子进程可能还没打开它。
  os.remove(script)
  return output, ok, code
end

return bash