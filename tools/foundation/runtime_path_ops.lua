local runtime_path_ops = {}

function runtime_path_ops.normalize(path)
  return tostring(path or ""):gsub("\\", "/")
end

function runtime_path_ops.strip_source_prefix(path)
  return runtime_path_ops.normalize(path):gsub("^@", "")
end

function runtime_path_ops.join(base, child)
  local normalized_base = runtime_path_ops.normalize(base):gsub("/+$", "")
  local normalized_child = runtime_path_ops.normalize(child):gsub("^/+", "")
  if normalized_base == "" then
    return normalized_child
  end
  if normalized_child == "" then
    return normalized_base
  end
  return normalized_base .. "/" .. normalized_child
end

function runtime_path_ops.dirname(path)
  local normalized = runtime_path_ops.normalize(path)
  return normalized:match("^(.*)/[^/]+$") or "."
end

-- MSYS 形态 /d/dev/... → D:/dev/...(内部口径只认正斜杠 Windows 绝对路径)。
-- 盘符形态与已是相对的形态原样返回。
local function _normalize_msys_path(value)
  local normalized = runtime_path_ops.normalize(value)
  local drive, rest = normalized:match("^/(%a)/(.*)$")
  if drive ~= nil then
    return drive:upper() .. ":/" .. rest
  end
  return normalized
end

-- 当前目录真源是 `cygpath -a -m .`(ADR 0083):它把 cwd 直接给出 D:/… 形态。
-- 本机实测的两个坑:`cygpath -m .` 返回相对形式 ".",`pwd -W` 在 MSYS bash 下
-- 不支持,所以只用 -a -m。PWD 只在起不了子进程时兜底,且要先把 MSYS 形态归一。
-- 不能直接信 PWD:Python subprocess(cwd=...) 起子进程时只改真实 cwd,不更新
-- 继承来的 PWD(mutator 就是这样起 worker 的),照抄 PWD 会把父进程目录当 cwd。
-- 本文件被 bootstrap 在 package.path 装好之前 dofile,所以只能用本文件内的纯 Lua
-- 原语:io.popen 起 bash 要显式给解释器,不能 require foundation.bash。
function runtime_path_ops.current_dir()
  local bash_lib = _G.__monopoly_runtime_bash
  if bash_lib == nil then
    local ok, loaded = pcall(require, "foundation.bash")
    if ok then
      bash_lib = loaded
      _G.__monopoly_runtime_bash = loaded
    end
  end

  if bash_lib ~= nil then
    -- 经执行缝跑 cygpath:io.popen 在原生 Windows 上走 cmd.exe,单引号与
    -- `2>/dev/null` 都不成立,拿到的不是 cygpath 的输出而是 cmd 的报错。
    local output = bash_lib.capture("cygpath -a -m .")
    if output ~= nil then
      local normalized = runtime_path_ops.normalize(output):gsub("%s+$", "")
      if normalized ~= "" then
        return _normalize_msys_path(normalized)
      end
    end
  end

  local env_cwd = os.getenv("PWD")
  if env_cwd ~= nil and env_cwd ~= "" then
    return _normalize_msys_path(env_cwd)
  end
  return "."
end

-- 存在性判定纯 Lua:io.open 可读 → 存在;打不开时用 os.rename(p, p) 兜底(无权限读的
-- 目录仍可 rename 成功)。不起子进程。
--
-- 目录判定(ADR 0083):原生 Windows 上 io.open 对**目录**返回 nil、对普通文件返回句柄,
-- 所以「打不开 + rename 成立」= 是目录。旧口径 io.open(p.."/.") 在这里把谓词反了。
function runtime_path_ops.path_exists(path)
  if path == nil or path == "" then
    return false
  end
  local file = io.open(path, "rb")
  if file ~= nil then
    file:close()
    return true
  end
  -- 目录打不开(原生 Windows 上 io.open 对目录返回 nil)。
  -- 判据:在 <path>/ 下真建一个临时文件——目录建得出来,普通文件与缺失路径都
  -- 建不出来。不用 os.rename(p, p):它对目录间歇性失败(实测 100 次里失败 13 次),
  -- 拿它当唯一判据会让仓根定位时好时坏。
  local probe = path .. "/.__monopoly_exists_probe_" .. tostring({}):gsub("[^%w]+", "")
  local handle = io.open(probe, "wb")
  if handle == nil then
    return false
  end
  handle:close()
  os.remove(probe)
  return true
end

-- 绝对路径判定(ADR 0083):盘符形态 D:/… / C:/… 与 POSIX 根 "/" 都算绝对。
-- /c/… 与 /d/… 的 MSYS 形态虽然也以 / 开头,但它不是内部口径——归一由调用方负责。
function runtime_path_ops.is_absolute(path)
  local normalized = runtime_path_ops.normalize(path)
  return normalized:sub(1, 1) == "/" or normalized:match("^%a:/") ~= nil
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

function runtime_path_ops.parent_dir(path)
  local normalized = runtime_path_ops.normalize(path):gsub("/+$", "")
  local parent = normalized:match("^(.*)/[^/]+$")
  if parent == nil or parent == "" then
    return normalized
  end
  return parent
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
-- 所以这里只能用本文件内的纯 Lua 原语,不得 require。
function runtime_path_ops.resolve(opts)
  opts = opts or {}

  local cwd = runtime_path_ops.normalize(opts.cwd or runtime_path_ops.current_dir())
  local source_path = runtime_path_ops.resolve_source_path(
    opts.source_path or opts.script_path or opts.module_source or "",
    cwd
  )
  local script_dir = source_path
  if source_path:match("%.lua$") ~= nil then
    script_dir = runtime_path_ops.dirname(source_path)
  end

  local probe = script_dir
  while probe ~= "" do
    if _looks_like_repo_root(probe) then
      return {
        source_path = source_path,
        script_dir = script_dir,
        repo_root = probe,
        tools_dir = runtime_path_ops.join(probe, "tools"),
      }
    end

    local parent = runtime_path_ops.parent_dir(probe)
    if parent == probe or parent == "" then
      break
    end
    probe = parent
  end

  error("failed to resolve repo_root from source path: " .. tostring(source_path))
end

return runtime_path_ops
