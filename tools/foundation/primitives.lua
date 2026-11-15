-- primitives.lua —— 全仓唯一的 os/io 原语叶子(ADR 0083 深化)。
--
-- 为什么要有这个文件:执行缝(foundation.bash)、cwd 探测(runtime_path_ops)、受控环境核对
-- (lua_env)、平台判决(platform_boundary)、第一块砖(package_path_helper)都必须在
-- package.path 装好**之前**运行,那时 require 不可用,于是各自重写"反斜杠归一 / 存在性
-- 探测 / POSIX 引号 / 临时名熵"这些一行原语,靠注释"与其他模块同口径"手工同步。
-- 这个叶子把它们收成一份。
--
-- 硬约束(测试 test_primitives.lua 钉住):
--   * 顶层零 require —— 一旦 require,就无法在 package.path 装好前 dofile;
--   * 只碰 os / io / string / table / debug,不落盘、不起进程、不读项目模块;
--   * 无 error、无 os.exit:探测类返回状态词,失败由调用方判不可用(退 3)。
-- 反向不成立:本文件不依赖任何 foundation 模块,所以 shell→env→fs→shell 的环不可能形成。

local primitives = {}

local _registry = {}

-- 反斜杠归一。全仓"内部路径一律正斜杠"的唯一产生点(ADR 0083 第 4 条)。
function primitives.normalize(value)
  return (tostring(value or ""):gsub("\\", "/"))
end

-- MSYS 形态 /d/dev/... → D:/dev/...(原生 Lua 的 io.open 只认后者)。
-- 盘符形态与相对形态原样返回。
function primitives.to_native_drive(value)
  local normalized = primitives.normalize(value)
  local drive, rest = normalized:match("^/(%a)/(.*)$")
  if drive ~= nil then
    return drive:upper() .. ":/" .. rest
  end
  return normalized
end

-- 临时目录:读**原生进程**的 TEMP/TMP,缺省 C:/Windows/Temp。
-- 不读 TMPDIR、不用 /tmp:原生 Lua 的 io.open 打不开 MSYS 的 /tmp,
-- Git Bash 又会把继承来的 TMP 覆盖成 /tmp。
function primitives.tmp_dir()
  local value = os.getenv("TEMP")
  if value == nil or value == "" then
    value = os.getenv("TMP")
  end
  if value == nil or value == "" then
    value = "C:/Windows/Temp"
  end
  return (tostring(value):gsub("\\", "/"):gsub("/+$", ""))
end

-- 唯一名:计数器 + 墙钟 + 对象地址,足以在同一进程内不撞。
-- 不是安全随机源(标记/临时名不承担安全语义)。
local _counter = 0
function primitives.unique_name(prefix, suffix)
  _counter = _counter + 1
  local token = tostring({}):gsub("[^%w]+", "")
  if token == "" then token = "ptr" end
  return table.concat({
    tostring(prefix or "tmp"), "_", tostring(os.time()), "_", tostring(_counter), "_", token,
    tostring(suffix or ""),
  })
end

-- 存在性判定:只读、无副作用(ADR 0083 / #234 F7)。
-- 判据来自 io.open 的 errno,不写探针文件、不起子进程:
--   打开成功 → 普通(可读)文件;
--   ENOENT(2) → 不存在;
--   EACCES(13)/EPERM(1)/EISDIR(21) → 目录(原生 Windows 对目录一律 ERROR_ACCESS_DENIED);
--   其他 errno → "unknown",由调用方经执行缝 test -d / test -e 仲裁。
local _ENOENT, _EPERM, _EACCES, _EISDIR = 2, 1, 13, 21

function primitives.probe_path(path)
  if path == nil or path == "" then
    return "missing"
  end
  local handle, _, errno = io.open(path, "rb")
  if handle ~= nil then
    handle:close()
    return "file"
  end
  if errno == _ENOENT then
    return "missing"
  end
  if errno == _EACCES or errno == _EPERM or errno == _EISDIR then
    return "dir"
  end
  return "unknown"
end

function primitives.exists(path)
  return primitives.probe_path(path) ~= "missing"
end

function primitives.readable(path)
  local handle = io.open(path, "rb")
  if handle == nil then
    return false
  end
  handle:close()
  return true
end

-- POSIX 单引号:内部单引号写成 '\''。恒引号形态,用于命令参数。
function primitives.quote(value)
  local text = tostring(value or "")
  assert(not text:find("[\r\n%z]"), "Command arguments cannot contain NUL or newlines")
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- 能省则省形态(lua_env 拼 env -u 前缀用):安全字符不加引号。
-- 与 quote 是两种形态,不能合并——合并会改写 lua_env 生成的命令行文本。
function primitives.quote_if_needed(value)
  local text = tostring(value or "")
  assert(not text:find("[\r\n%z]"), "Command arguments cannot contain NUL or newlines")
  if text:match("^[%w%-%._/:=]+$") ~= nil then
    return text
  end
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- 自身目录(正斜杠形态)。level 是 debug.getinfo 的栈层,缺省 1 = 本函数调用者。
function primitives.self_dir(level)
  local source = tostring(debug.getinfo((level or 1) + 1, "S").source or "")
  local normalized = primitives.normalize(source:gsub("^@", ""))
  return normalized:match("^(.*)/[^/]+$") or "."
end

-- 兄弟模块的唯一加载器:require 命中即用,否则按本文件位置 loadfile。
--
-- 为什么需要它:同一个模块会在两种装载面下被取用——package.path 装好后走 require,
-- 装好前(tools/ 不在搜索面上)只能 loadfile。两套各自实现会导致**同一模块被装载两次**,
-- 模块级状态(_resolved 缓存、临时名计数器)随之分裂。registry 保证进程内只装一次。
function primitives.shared(name)
  if _registry[name] ~= nil then
    return _registry[name]
  end
  local ok_require, loaded = pcall(require, "foundation." .. name)
  if ok_require and type(loaded) == "table" then
    _registry[name] = loaded
    return loaded
  end
  local chunk = loadfile(primitives.self_dir(1) .. "/" .. name .. ".lua")
  if chunk == nil then
    return nil
  end
  local ok_load, mod = pcall(chunk)
  if ok_load and type(mod) == "table" then
    _registry[name] = mod
    return mod
  end
  return nil
end

-- 自登记:本文件可能被 require、dofile、loadfile 三种方式装载。登记进 package.loaded 后,
-- 按 require 取到的就是同一张表。但 dofile/loadfile 仍会**重新执行**本文件,所以调用方
-- 必须先查 package.loaded 再决定是否装载(见 path.lua / runtime_path_ops.lua / bash.lua
-- 的取用段),否则模块级状态(unique_name 计数器、shared registry)会分裂。
package.loaded["foundation.primitives"] = primitives

return primitives
