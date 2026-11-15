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
-- 本模块刻意**不 require 任何 foundation 模块**:执行缝在依赖图最底层,
-- fs / proc / parallel_lanes / env 都依赖它。若它反向依赖 env(临时目录)或 fs(落盘),
-- 就会形成 shell→env→fs→shell 的环。它只取零依赖叶子 primitives(反斜杠归一 / 临时目录 /
-- 唯一名 / 存在性 / POSIX 引号),而且按**自身位置** loadfile 取,不走 require 边:
-- 执行缝要在 package.path 装好之前就能跑(见下方 _load_primitives)。环境变量仍直接 os.getenv。
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
-- unique_name 自己插一个分隔下划线(prefix .. "_" .. 时间 …),所以传去掉尾下划线的形态:
-- 生成的名字仍是 eggy_exec_<time>_<counter>_<token>.sh,与旧实现逐字节同形。
local _SCRIPT_NAME_PREFIX = _SCRIPT_PREFIX:gsub("_$", "")
local _resolved -- 发现结果:成功是路径字符串,失败是 false,未探测是 nil
local _last_unavailable

-- 原语叶子的取用:本模块会在 package.path 装好**之前**被 loadfile(lua_env 的受控环境
-- 核对、bootstrap 链上的 cygpath 探测),那时 require 未必可用,所以自己按源文件位置
-- loadfile 同目录的 primitives.lua。
--
-- 关键在**只装一次**:loadfile 出来的第二份 primitives 自带第二套 unique_name 计数器,
-- 与 require 取到的那份各数各的,临时脚本名就可能撞车。因此装载顺序是
-- package.loaded 命中 → require → loadfile,并且 loadfile 的分支把结果登记回
-- package.loaded,后续任何 require 拿到的都是同一张表(test_shell_execute.lua 钉住)。
local function _load_primitives()
  local cached = package.loaded["foundation.primitives"]
  if type(cached) == "table" then
    return cached
  end
  local ok_require, required = pcall(require, "foundation.primitives")
  if ok_require and type(required) == "table" then
    return required
  end
  local source = tostring(debug.getinfo(1, "S").source or ""):gsub("^@", ""):gsub("\\", "/")
  local dir = source:match("^(.*)/[^/]+$")
  if dir == nil then
    return nil
  end
  local chunk = loadfile(dir .. "/primitives.lua")
  if chunk == nil then
    return nil
  end
  local ok_load, loaded = pcall(chunk)
  if not ok_load or type(loaded) ~= "table" then
    return nil
  end
  package.loaded["foundation.primitives"] = loaded
  return loaded
end

local primitives = _load_primitives()
assert(type(primitives) == "table", "foundation.bash requires the primitives leaf next to it")

-- 内部路径口径:D:/… 正斜杠。TEMP/TMP 来自原生 Lua 进程,不读 bash 继承来的值
-- (Git Bash 会把 TMP 覆盖成 /tmp)。函数名保留:ADR 0083 第 4 条与 env.lua 按这个名调用,
-- 真源已下沉到 primitives.tmp_dir,这里只转发,不再留会漂移的副本。
function bash.system_tmp_dir()
  return primitives.tmp_dir()
end

-- WSL 的 C:/Windows/System32/bash.exe 也是一个 bash,但它跑不了原生 Windows 路径,
-- 发现到它等于把工具链扔进另一个操作系统(where bash 会把它列出来)。
local function _is_wsl_bash(file)
  return primitives.readable(file) and tostring(file):lower():find("/system32/bash", 1, true) ~= nil
end

local function _path_entries()
  local entries, seen = {}, {}
  local raw = os.getenv("PATH") or ""
  for entry in tostring(raw):gmatch("[^;]+") do
    local trimmed = primitives.normalize(entry):gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
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
  return primitives.normalize(value)
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
      if primitives.readable(candidate) and not _is_wsl_bash(candidate) then
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
      if primitives.readable(candidate) then
        list[#list + 1] = { source = "git-install", path = candidate }
      end
    end
  end
  return list
end

local function _temp_script_path()
  return primitives.tmp_dir() .. "/" .. primitives.unique_name(_SCRIPT_NAME_PREFIX, ".sh")
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
  -- marker 落在临时目录下:目录名带单引号时,手拼的 '…' 会被 bash 提前闭合、探针静默失败,
  -- 整台机器被误判「没有 bash」。引号统一交给 primitives.quote。
  handle:write("printf '%s' 'bash-ok' > " .. primitives.quote(marker) .. "\n")
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
    local pinned = primitives.normalize(override)
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

-- 唯一执行实现:命令文本写进临时脚本,交 bash 执行。执行 + 读回输出只有这一处,
-- 不再有第二个执行面(bash.capture 这个名字已删,#234 F1)。
--
-- 两种读回形态共用同一份脚本文件缝,由 options.capture 选:
--   * 默认:(ok, "exit"|"unavailable", code),与 os.execute 的 Lua 5.4 形态一致;
--   * options.capture = true:(output, ok, code),经 io.popen 把 stdout+stderr 读回。
-- 找不到 bash / 写不出脚本:默认 (nil, "unavailable", 3);capture (nil, nil, 3),
-- 两种情况都记下具体原因。
--
-- 对外公开入口是 foundation.shell.execute(转发到这里);本函数是实现层,只有必须在
-- package.path 装好前运行的基础模块(lua_env 的受控环境核对、runtime_path_ops 的
-- cygpath 探测)才直接调用它,且同样只走这一份实现。
function bash.execute(command, options)
  options = options or {}
  local executable, reason = bash.discover(options.bash)
  if executable == nil then
    _last_unavailable = reason
    if options.capture then
      return nil, nil, bash.UNAVAILABLE_EXIT_CODE
    end
    return nil, "unavailable", bash.UNAVAILABLE_EXIT_CODE
  end

  local script = _temp_script_path()
  local handle = io.open(script, "wb")
  if handle == nil then
    _last_unavailable = "cannot write command script under " .. bash.system_tmp_dir()
    if options.capture then
      return nil, nil, bash.UNAVAILABLE_EXIT_CODE
    end
    return nil, "unavailable", bash.UNAVAILABLE_EXIT_CODE
  end
  local body = tostring(command or "")
  handle:write(body)
  if body:sub(-1) ~= "\n" then
    handle:write("\n")
  end
  handle:close()

  if options.capture then
    local pipe = io.popen(_command_line(executable, script) .. " 2>&1")
    if pipe == nil then
      os.remove(script)
      _last_unavailable = "cannot start bash for output capture"
      return nil, nil, bash.UNAVAILABLE_EXIT_CODE
    end
    local output = pipe:read("*a") or ""
    local ok, _, code = pipe:close()
    -- 脚本必须在子进程读完(close 等到收场)之后再删:popen 返回时子进程可能还没打开它。
    os.remove(script)
    return output, ok, code
  end

  local ok, kind, code = os.execute(_command_line(executable, script))
  os.remove(script)
  return ok, kind, code
end

return bash