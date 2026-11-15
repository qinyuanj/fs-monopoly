-- 文件系统 IO:读写文件、建删目录、拷贝。
--
-- 测试正是靠替换 foundation.fs.path_exists 这类字段来控制环境分支的。
-- 那个替身注入点在**调用方**边界上——调用方直接 require 本模块的表,字段可整体替换。
-- 但注意:本模块内部互调走 fs.xxx,替身穿不进来,别指望 stub fs.path_exists 能改掉
-- fs.remove_path 的行为。
--
-- 原生 Windows 单平台(ADR 0083):Lua 二进制 IO + POSIX 原语(mkdir -p / rm -rf /
-- cp -R,一律经 foundation.shell.execute 交 bash)。存在性与目录判定是纯 Lua
-- (不起子进程),只有真正改动文件系统的操作才走执行缝。
local text_lib = require("foundation.text")
local path_lib = require("foundation.path")
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
-- 必须显式收成一个布尔再 return:谓词就该只答"是/否",不能把执行缝的
-- (成功, 退出码) 一对值继续往上传。
--
-- 存在性判定纯 Lua:io.open 可读 → 存在;否则 os.rename(p, p) 兜底(无读权限的目录
-- 仍可 rename 成功)。
--
-- 目录判定(ADR 0083):原生 Windows 上 io.open 对**目录**返回 nil、对普通文件返回句柄,
-- 所以「打不开 + rename 成立」= 是目录。旧口径 io.open(p.."/.") 在这里把谓词反了。
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
  if fs.is_readable(normalized) then
    return true
  end
  -- 打不开时可能是目录:在 <path>/ 下真建一个临时文件来判(目录建得出来,
  -- 普通文件与缺失路径都建不出来)。不用 os.rename(p, p):它对目录间歇性失败
  -- (实测 100 次里失败 13 次),拿它当唯一判据会让目录时有时无。
  local probe = normalized .. "/.__monopoly_exists_probe_" .. tostring({}):gsub("[^%w]+", "")
  local handle = io.open(probe, "wb")
  if handle == nil then
    return false
  end
  handle:close()
  os.remove(probe)
  return true
end

-- 目录判定:纯 Lua,不起子进程。
--
-- 判据一:io.open 能打开 → 是普通文件,不是目录(原生 Windows 上 io.open 对目录
-- 返回 nil、对普通文件返回句柄)。
-- 判据二:在 <path>/ 下真建一个临时文件 → 是目录(普通文件与缺失路径都建不出来)。
-- 判据二是主判据:os.rename(p, p) 对目录**间歇性**失败(实测同一目录 100 次里失败
-- 13 次,且只在有并发子进程时明显),拿它当唯一判据会让仓根定位时好时坏。
-- 注意别用旧的 io.open(p.."/.") 口径:它在 Windows 上对普通文件也成功,谓词是反的。
function fs.is_dir(path)
  if path == nil or path == "" then
    return false
  end
  local normalized = path_lib.normalize_path(path):gsub("/+$", "")
  if normalized == "" then
    return false
  end
  if fs.is_readable(normalized) then
    return false
  end
  local probe = normalized .. "/.__monopoly_is_dir_probe_" .. tostring({}):gsub("[^%w]+", "")
  local handle = io.open(probe, "wb")
  if handle == nil then
    return false
  end
  handle:close()
  os.remove(probe)
  return true
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