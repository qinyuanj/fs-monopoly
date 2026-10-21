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

-- 当前目录以 `pwd -L` 为准,PWD 只在起不了子进程时兜底。
-- 不能直接信 PWD:Python subprocess(cwd=...) 起子进程时只改真实 cwd,不更新
-- 继承来的 PWD(mutator 就是这样起 worker 的),照抄 PWD 会把父进程目录当 cwd。
-- `pwd -L` 保留逻辑路径(不解析符号链接),且 shell 会核对 PWD 是否仍指向当前
-- 目录,失配时按真实 cwd 输出。
function runtime_path_ops.current_dir()
  local process = io.popen("pwd -L 2>/dev/null")
  if process ~= nil then
    local output = process:read("*a") or ""
    process:close()
    local normalized = runtime_path_ops.normalize(output):gsub("%s+$", "")
    if normalized ~= "" then
      return normalized
    end
  end

  local env_cwd = os.getenv("PWD")
  if env_cwd ~= nil and env_cwd ~= "" then
    return runtime_path_ops.normalize(env_cwd)
  end
  return "."
end

-- 存在性判定纯 Lua:io.open 对目录同样返回句柄;打不开时用 os.rename(p, p)
-- 兜底(无权限读的目录仍可 rename 成功)。不起子进程。
function runtime_path_ops.path_exists(path)
  if path == nil or path == "" then
    return false
  end
  local file = io.open(path, "rb")
  if file ~= nil then
    file:close()
    return true
  end
  return os.rename(path, path) ~= nil
end

function runtime_path_ops.is_absolute(path)
  local normalized = runtime_path_ops.normalize(path)
  return normalized:sub(1, 1) == "/" or normalized:match("^%a:[/]") ~= nil
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

return runtime_path_ops
