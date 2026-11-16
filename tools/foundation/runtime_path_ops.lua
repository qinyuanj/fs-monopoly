-- runtime_path_ops —— 只保留**运行时事实**,路径代数一律转发 foundation.path。
--
-- 本文件被 bootstrap.lua 在 package.path 装好之前 dofile,所以拿同目录模块只能
-- loadfile 不能 require(见下面的加载段)。两种装载面(path 未装好 / 已装好)必须
-- 给出同一个答案:旧实现在 current_dir 里用 pcall(require, "foundation.bash") 试探,
-- 装好前静默失败落到 PWD、装好后走 cygpath,同一个函数两种答案。现在统一走 loadfile。
local runtime_path_ops = {}

-- 同目录模块的取法:先按**本文件自身位置** loadfile primitives(此刻可能还没有
-- package.path,require 不可用),再用它的 shared 取兄弟模块。shared 是唯一的加载器,
-- 这里不再自造第二套 require-or-loadfile。
local _self_source = tostring(debug.getinfo(1, "S").source or ""):gsub("^@", ""):gsub("\\", "/")
local _self_dir = _self_source:match("^(.*)/[^/]+$") or "tools/foundation"
-- 先查 package.loaded:裸 loadfile 会造出第二套 unique_name 计数器与 registry,
-- 与 require 取到的那份各数各的,临时名会撞车(test_primitives_shared_instance.lua 钉住)。
local function _load_primitives()
  local cached = package.loaded["foundation.primitives"]
  if type(cached) == "table" then
    return cached
  end
  local chunk = assert(loadfile(_self_dir .. "/primitives.lua"),
    "foundation.primitives must sit next to runtime_path_ops")
  local loaded = assert(chunk(), "foundation.primitives must load")
  package.loaded["foundation.primitives"] = loaded
  return loaded
end

local primitives = _load_primitives()
local path_lib = assert(primitives.shared("path"), "foundation.path must be loadable next to runtime_path_ops")

-- 以下是薄转发:名字保留是因为 bootstrap 与 test_native_primitives 在用,
-- 但实现只有 path 一份(ADR 0083 深化:叶子各自重写同一批原语正是要消掉的问题)。
function runtime_path_ops.normalize(value)
  return path_lib.normalize_path(value)
end

function runtime_path_ops.strip_source_prefix(value)
  return runtime_path_ops.normalize(value):gsub("^@", "")
end

function runtime_path_ops.join(base, child)
  return path_lib.join_path(base, child)
end

function runtime_path_ops.is_absolute(value)
  return path_lib.is_absolute_path(value)
end

-- 当前目录真源是 cygpath -a -m .(ADR 0083):它把 cwd 直接给出 D:/… 形态。
-- 本机实测的两个坑:cygpath -m . 返回相对形式 ".",pwd -W 在 MSYS bash 下
-- 不支持,所以只用 -a -m。PWD 只在起不了子进程时兜底,且要先把 MSYS 形态归一。
-- 不能直接信 PWD:Python subprocess(cwd=...) 起子进程时只改真实 cwd,不更新
-- 继承来的 PWD(mutator 就是这样起 worker 的),照抄 PWD 会把父进程目录当 cwd。
function runtime_path_ops.current_dir()
  local bash_lib = primitives.shared("bash")
  if bash_lib ~= nil then
    -- 经执行缝跑 cygpath:io.popen 在原生 Windows 上走 cmd.exe,单引号与
    -- 2>/dev/null 都不成立,拿到的不是 cygpath 的输出而是 cmd 的报错。
    -- capture 形态返回 (output, ok, code);必须核对退出码:cygpath 缺席时 stderr
    -- 会被 2>&1 合流读回,把报错文本当 cwd 会让仓根定位漂到子进程目录以外(#234 F8)。
    local output, ok, code = bash_lib.execute("cygpath -a -m .", { capture = true })
    if output ~= nil and ok == true and (code == nil or code == 0) then
      local normalized = runtime_path_ops.normalize(output):gsub("%s+$", "")
      if normalized ~= "" then
        return primitives.to_native_drive(normalized)
      end
    end
  end

  local env_cwd = os.getenv("PWD")
  if env_cwd ~= nil and env_cwd ~= "" then
    return primitives.to_native_drive(env_cwd)
  end
  return "."
end

-- 存在性 / 目录判定:**只读、无副作用**(ADR 0083 / #234 F7)。
-- 判据(errno)只有一份,在 primitives.probe_path;这里转发。
function runtime_path_ops.probe_path(path)
  return primitives.probe_path(path)
end

-- bootstrap 在 package.path 装好前用它,所以只走纯 Lua probe_path(不 require、不起进程)。
-- "unknown" 按存在处理:让后续真实 IO 自己报错,不在这里静默判缺失。
function runtime_path_ops.path_exists(path)
  return runtime_path_ops.probe_path(path) ~= "missing"
end

function runtime_path_ops.is_dir(path)
  return runtime_path_ops.probe_path(path) == "dir"
end

function runtime_path_ops.resolve_source_path(source_path, cwd)
  local normalized_source = runtime_path_ops.strip_source_prefix(source_path)
  if normalized_source == "" then
    return runtime_path_ops.normalize(cwd or ".")
  end
  if runtime_path_ops.is_absolute(normalized_source) then
    return normalized_source
  end
  return runtime_path_ops.join(cwd or ".", normalized_source)
end

local function _looks_like_repo_root(path)
  local required_entries = {
    "src",
    "test",
    "tools",
    "tools/cli.lua",
  }

  for _, entry in ipairs(required_entries) do
    if runtime_path_ops.path_exists(runtime_path_ops.join(path, entry)) ~= true then
      return false
    end
  end

  return true
end

-- 从源文件路径上溯定位仓根。bootstrap 在 package.path 装好之前经 dofile 装载本文件,
-- 所以这里只能用同目录 loadfile 拿到的叶子,不得 require。
--
-- 上溯终止条件:path.split_parent 无父返回 nil。旧实现让 parent_dir 无父时回传入参,
-- 循环靠 parent == probe 才停;现在 nil 就是唯一的终止信号。
function runtime_path_ops.resolve(opts)
  opts = opts or {}

  local cwd = runtime_path_ops.normalize(opts.cwd or runtime_path_ops.current_dir())
  local source_path = runtime_path_ops.resolve_source_path(
    opts.source_path or opts.script_path or opts.module_source or "",
    cwd
  )
  local script_dir = source_path
  if source_path:match("%.lua$") ~= nil then
    -- 无父(裸文件名,如 "probe.lua")时退回当前目录,不把 "" 当目录上溯。
    script_dir = path_lib.split_parent(source_path) or "."
  end

  local probe = script_dir
  while probe ~= nil and probe ~= "" do
    if _looks_like_repo_root(probe) then
      return {
        source_path = source_path,
        script_dir = script_dir,
        repo_root = probe,
        tools_dir = runtime_path_ops.join(probe, "tools"),
      }
    end

    local parent = path_lib.split_parent(probe)
    if parent == nil or parent == probe then
      break
    end
    probe = parent
  end

  error("failed to resolve repo_root from source path: " .. tostring(source_path))
end

-- 仓库自身模块的搜索模式(7 条),按装载优先级从低到高排列。
-- 原来是 package_path_helper.lua 的职责,但它必须"自包含"只是因为 bootstrap 会从
-- **解析出的仓根**去 dofile 它;搬到这里后 install 只从本文件(自身目录)取,不再
-- 依赖仓根里存在某个具体文件,那条自包含约束随之消失。
-- 纯数据 + 纯拼接,不碰 package.path,可单测。
local _PACKAGE_PATTERNS = {
  "tools/?.lua",
  "tools/?/init.lua",
  "test/?.lua",
  "test/?/init.lua",
  "test/fixtures/?.lua",
  "?.lua",
  "?/init.lua",
}

function runtime_path_ops.package_patterns(repo_root)
  local root = runtime_path_ops.normalize(repo_root)
  local patterns = {}
  for index, relative in ipairs(_PACKAGE_PATTERNS) do
    patterns[index] = runtime_path_ops.join(root, relative)
  end
  return patterns
end

-- 把 7 条模式前置进 package.path(已存在的跳过,故可重复调用)。
-- 逆序前置:最终顺序与 _PACKAGE_PATTERNS 一致。
function runtime_path_ops.install_eggy_package_paths(repo_root)
  local patterns = runtime_path_ops.package_patterns(repo_root)
  for index = #patterns, 1, -1 do
    local pattern = patterns[index]
    if not tostring(package.path):find(pattern, 1, true) then
      package.path = pattern .. ";" .. package.path
    end
  end
end

return runtime_path_ops
