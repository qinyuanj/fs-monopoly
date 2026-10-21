-- 文件系统 IO:读写文件、建删目录、拷贝。
--
-- 测试正是靠替换 foundation.fs.path_exists 这类字段来控制环境分支的。
-- 那个替身注入点在**调用方**边界上——调用方直接 require 本模块的表,字段可整体替换。
-- 但注意:本模块内部互调走 fs.xxx,替身穿不进来,别指望 stub fs.path_exists 能改掉
-- fs.remove_path 的行为。
--
-- WSL Ubuntu 单平台(ADR 0073):Lua 二进制 IO + POSIX 原语(mkdir -p / rm -rf /
-- cp -R)。存在性与目录判定是纯 Lua(不起子进程),只有真正改动文件系统的操作
-- 才走 shell。
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

local function _write_raw_file(path, content, mode)
  local file = io.open(path, mode or "wb")
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
  local ok, kind, code = os.execute("mkdir -p " .. shell_lib.shell_quote(normalized))
  local success = shell_lib.exit_status(ok, kind, code)
  if not success then
    return nil, text_lib.bilingual_with_suffix("创建目录失败: ", "Failed to create directory: ", path)
  end
  return true
end

function fs.ensure_parent_dir(path)
  return fs.ensure_dir(path_lib.parent_dir(path))
end

-- write_file / append_file 只差一个写入模式。差异参数化,流程只留一份。
local function _write_file_with_mode(path, content, mode)
  local ok, err = fs.ensure_parent_dir(path)
  if not ok then
    return nil, err
  end

  local appending = mode == "append"
  local normalized = path_lib.normalize_path(path)
  local write_ok = _write_raw_file(normalized, tostring(content or ""), appending and "ab" or "wb")
  if write_ok == nil then
    return nil, text_lib.bilingual_with_suffix(
      "无法" .. (appending and "追加" or "写入") .. "文件: ",
      "Cannot " .. (appending and "append" or "write") .. " file: ",
      path
    )
  end
  return true
end

function fs.write_file(path, content)
  return _write_file_with_mode(path, content, "write")
end

function fs.append_file(path, content)
  return _write_file_with_mode(path, content, "append")
end

-- path_exists / is_dir 只差一个判定谓词(存在 vs 是目录)。
--
-- 必须显式收成一个布尔再 return:谓词就该只答"是/否",不能把 os.execute 的
-- (成功, 退出码) 一对值继续往上传。
--
-- 判定用纯 Lua 的 `path/.` 探测:io.open("dir/.") 对目录成功、对普通文件失败;
-- io.open(path) 对文件和目录都成功。这样既不起子进程,也不受 shell 引号与
-- 文件名特殊字符影响。
local function _openable(path)
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
  if _openable(normalized) or _openable(normalized .. "/.") then
    return true
  end
  -- 不可读目录:rename 自身在无读权限时仍成立。
  return os.rename(normalized, normalized) ~= nil
end

function fs.is_dir(path)
  if path == nil or path == "" then
    return false
  end
  return _openable(path_lib.normalize_path(path) .. "/.")
end

function fs.remove_path(path)
  if not fs.path_exists(path) then
    return true
  end

  local normalized = path_lib.normalize_path(path)
  local ok, kind, code = os.execute("rm -rf " .. shell_lib.shell_quote(normalized))
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
  local exec_ok, kind, code = os.execute(command)
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
