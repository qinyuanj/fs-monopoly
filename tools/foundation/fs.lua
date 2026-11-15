-- 文件系统 IO:读写文件、建删目录、拷贝。
--
-- 测试正是靠替换 foundation.fs.path_exists 这类字段来控制环境分支的。
-- 那个替身注入点在**调用方**边界上——调用方直接 require 本模块的表,字段可整体替换。
-- 但注意:本模块内部互调走 fs.xxx,替身穿不进来,别指望 stub fs.path_exists 能改掉
-- fs.remove_path 的行为。
--
-- 原生 Windows 单平台(ADR 0083):Lua 二进制 IO + POSIX 原语(mkdir -p / rm -rf /
-- cp -R,一律经 foundation.shell.execute 交 bash)。存在性与目录判定默认是纯 Lua、
-- **无副作用**(不写探针文件,见 runtime_path_ops.probe_path);只有真正改动文件系统
-- 的操作、以及 errno 不可判时的兜底仲裁,才走执行缝。
local text_lib = require("foundation.text")
local path_lib = require("foundation.path")
local runtime_path_ops = require("foundation.runtime_path_ops")
local shell_lib = require("foundation.shell")

local fs = {}

function fs.read_raw(path)
  local file = io.open(path, "rb")
  if file == nil then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function _write_raw_file(path, content)
  local file = io.open(path, "wb")
  if file == nil then
    return nil
  end
  file:write(content)
  file:close()
  return true
end

function fs.read_file(path)
  local normalized = path_lib.normalize_path(path)
  local content = fs.read_raw(normalized)
  if content ~= nil then
    return content
  end
  return nil, text_lib.bilingual_with_suffix("无法打开文件: ", "Cannot open file: ", path)
end

function fs.ensure_dir(path)
  if path == nil or path == "" then
    return true
  end

  local normalized = path_lib.normalize_path(path)
  -- 已是目录时 `mkdir -p` 什么也不做;纯 Lua 探测先答掉,免去每次 write_file /
  -- copy_file 都起一个 shell(批量复制时是数千次子进程)。
  if fs.is_dir(normalized) then
    return true
  end
  local ok, kind, code = shell_lib.execute("mkdir -p " .. shell_lib.shell_quote(normalized))
  local success = shell_lib.exit_status(ok, kind, code)
  if not success then
    return nil, text_lib.bilingual_with_suffix("创建目录失败: ", "Failed to create directory: ", path)
  end
  return true
end

function fs.ensure_parent_dir(path)
  return fs.ensure_dir(path_lib.parent_dir(path))
end

function fs.write_file(path, content)
  local ok, err = fs.ensure_parent_dir(path)
  if not ok then
    return nil, err
  end

  local normalized = path_lib.normalize_path(path)
  if _write_raw_file(normalized, tostring(content or "")) == nil then
    return nil, text_lib.bilingual_with_suffix("无法写入文件: ", "Cannot write file: ", path)
  end
  return true
end

-- path_exists / is_dir 只差一个判定谓词(存在 vs 是目录)。
--
-- 判定统一来自 runtime_path_ops.probe_path(io.open 的 errno):纯 Lua、不起子进程、
-- **不写任何文件**(#234 F7——旧实现会在目标目录建探针文件再删,deploy-diff 因此
-- 在部署目录里写了东西,不可写目录还被判成不存在而误退 1)。
--
-- 只有 errno 落在预期集合之外("unknown")时,才经统一执行缝 `test -e` / `test -d`
-- 仲裁:执行缝仍是唯一的权威兜底,但不进写文件/判目录的热路径。
local function _seam_probe(flag, path)
  local command = "test " .. flag .. " " .. shell_lib.shell_quote(path)
  local ok, kind, code = shell_lib.execute(command)
  return shell_lib.exit_status(ok, kind, code) == true
end

function fs.is_readable(path)
  local handle = io.open(path, "rb")
  if handle == nil then
    return false
  end
  handle:close()
  return true
end

function fs.path_exists(path)
  if path == nil or path == "" then
    return false
  end
  local normalized = path_lib.normalize_path(path)
  local state = runtime_path_ops.probe_path(normalized)
  if state == "missing" then
    return false
  end
  if state == "unknown" then
    return _seam_probe("-e", normalized)
  end
  return true
end

-- 目录判定:同一条 probe_path;file / missing 直接否,dir 直接是,unknown 才问执行缝。
-- 全程不写任何文件。
function fs.is_dir(path)
  if path == nil or path == "" then
    return false
  end
  local normalized = path_lib.normalize_path(path):gsub("/+$", "")
  if normalized == "" then
    return false
  end
  local state = runtime_path_ops.probe_path(normalized)
  if state == "dir" then
    return true
  end
  if state == "unknown" then
    return _seam_probe("-d", normalized)
  end
  return false
end

function fs.remove_path(path)
  if not fs.path_exists(path) then
    return true
  end

  local normalized = path_lib.normalize_path(path)
  local ok, kind, code = shell_lib.execute("rm -rf " .. shell_lib.shell_quote(normalized))
  local success = shell_lib.exit_status(ok, kind, code)
  if not success then
    return nil, text_lib.bilingual_with_suffix("删除路径失败: ", "Failed to remove path: ", path)
  end
  return true
end

function fs.copy_file(source_path, target_path)
  local ok, err = fs.ensure_parent_dir(target_path)
  if not ok then
    return nil, err
  end
  local source_text, read_err = fs.read_file(source_path)
  if source_text == nil then
    return nil, read_err
  end
  return fs.write_file(target_path, source_text)
end

-- 目录镜像:先删目标再整体拷贝,与先前 robocopy /MIR 的可观察结果一致
-- (目标侧陈旧文件消失,源侧隐藏项与空目录保留)。
function fs.copy_tree(source_path, target_path)
  local normalized_source = path_lib.normalize_path(source_path)
  local normalized_target = path_lib.normalize_path(target_path)
  local removed, remove_err = fs.remove_path(normalized_target)
  if not removed then
    return nil, remove_err
  end

  local ok, err = fs.ensure_parent_dir(normalized_target)
  if not ok then
    return nil, err
  end

  local command = "cp -R "
    .. shell_lib.shell_quote(normalized_source)
    .. " "
    .. shell_lib.shell_quote(normalized_target)
  local exec_ok, kind, code = shell_lib.execute(command)
  local success, exit_code = shell_lib.exit_status(exec_ok, kind, code)
  if not success then
    return nil, text_lib.bilingual_with_suffix(
      "目录拷贝失败，退出码: ",
      "Copy tree failed with exit code: ",
      exit_code
    )
  end
  return true
end

return fs