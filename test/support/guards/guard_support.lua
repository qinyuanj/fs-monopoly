local proc_lib = require("foundation.proc")
local fs_lib = require("foundation.fs")
local env_lib = require("foundation.env")

local M = {}

local function _is_file_path(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

-- 存在性判定复用 foundation.fs:纯 Lua 探测(io.open + 目录探针文件),不用
-- os.rename(p, p)——原生 Windows 上它对目录间歇性失败,会把「目录存在」误判成「不存在」。
function M.path_exists(path)
  return fs_lib.path_exists(path)
end

-- 把枚举得到的绝对路径折回仓内相对形态,与旧 `find <相对根>` 输出口径一致:
-- dep_rules 的行级白名单按 "src/…"/"tools/…"/"test/…" 这类相对路径登记,
-- 直接喂绝对路径会让白名单失配、把合法行误报成违规。
local function _to_repo_relative(path, base)
  local normalized = M.normalize_path(path)
  if base ~= "" and normalized:sub(1, #base + 1) == base .. "/" then
    return normalized:sub(#base + 2)
  end
  return normalized
end

-- 递归枚举 root 下的 .lua 文件(含隐藏文件与隐藏目录)。
--
-- 枚举走统一执行缝 foundation.proc.collect_lua_files(内部经 bash 跑 `find -print0`),
-- 不再自己起 io.popen("find …"):原生 Windows 的 io.popen 走 cmd.exe,cmd 的 find.exe
-- 不认 -type/-name/-print0 与 POSIX 单引号,进程一开就失败,守卫只会误报
-- 「list command failed」而不是真的判定违规。平台收窄要成为被测事实,不靠放宽守卫。
function M.collect_lua_files(root)
  local normalized_root = M.normalize_path(root)
  if normalized_root:match("%.lua$") then
    if _is_file_path(root) then
      return { root }
    end
    return nil, "no lua files found under root: " .. tostring(root)
  end
  if not M.path_exists(root) then
    return nil, "no lua files found under root: " .. tostring(root)
  end

  local absolute_files, err = proc_lib.collect_lua_files(root)
  if absolute_files == nil then
    -- 根不存在时 proc 报 "Directory does not exist";其余(find 真失败)保持可诊断。
    if tostring(err or ""):find("Directory does not exist", 1, true) then
      return nil, "no lua files found under root: " .. tostring(root)
    end
    return nil, "list command failed for root: " .. tostring(root)
  end

  local base = M.normalize_path(env_lib.current_dir())
  local files = {}
  for _, absolute in ipairs(absolute_files) do
    files[#files + 1] = _to_repo_relative(absolute, base)
  end

  if #files == 0 then
    return nil, "no lua files found under root: " .. tostring(root)
  end

  return files
end

function M.normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function _to_repo_relpath(path)
  local normalized = M.normalize_path(path)
  return normalized:match(".*(src/.+)")
    or normalized:match(".*(tests/.+)")
    or normalized:match(".*(tools/.+)")
    or normalized:match(".*(Config/.+)")
    or normalized:match(".*(docs/.+)")
    or normalized:match(".*(%.agents/.+)")
    or normalized
end

function M.is_comment_line(line)
  return tostring(line or ""):match("^%s*%-%-") ~= nil
end

local function _list_lua_files(roots, opts)
  opts = opts or {}
  local files = {}
  for _, root in ipairs(roots or {}) do
    local root_files, err = M.collect_lua_files(root)
    if not root_files then
      if opts.allow_empty_roots ~= true or not tostring(err):find("no lua files found under", 1, true) then
        return nil, err
      end
    else
      for _, path in ipairs(root_files) do
        local relpath = _to_repo_relpath(path)
        if opts.skip_path == nil or opts.skip_path(path, relpath) ~= true then
          files[#files + 1] = {
            path = path,
            relpath = relpath,
          }
        end
      end
    end
  end
  return files
end

function M.find_line_violation(opts)
  opts = opts or {}
  local files, err = _list_lua_files(opts.roots or {}, opts)
  if not files then
    return nil, err
  end

  for _, entry in ipairs(files) do
    local file = io.open(entry.path, "r")
    if not file then
      return nil, "cannot open: " .. tostring(entry.path)
    end

    local line_number = 0
    for line in file:lines() do
      line_number = line_number + 1
      local violation = opts.find_violation(entry.path, entry.relpath, line, line_number)
      if violation then
        file:close()
        return violation
      end
    end

    file:close()
  end

  return nil
end

function M.collect_line_violations(opts)
  opts = opts or {}
  local files, err = _list_lua_files(opts.roots or {}, opts)
  if not files then
    return nil, err
  end

  local violations = {}
  for _, entry in ipairs(files) do
    local file = io.open(entry.path, "r")
    if not file then
      return nil, "cannot open: " .. tostring(entry.path)
    end

    local line_number = 0
    for line in file:lines() do
      line_number = line_number + 1
      local violation = opts.find_violation(entry.path, entry.relpath, line, line_number)
      if violation then
        violations[#violations + 1] = violation
      end
    end

    file:close()
  end

  return violations
end

function M.skip_fixture_path(path, relpath)
  local normalized_path = M.normalize_path(path)
  local normalized_relpath = M.normalize_path(relpath)
  return normalized_path:find("test/fixtures/guards/", 1, true) ~= nil
    or normalized_relpath:find("test/fixtures/guards/", 1, true) ~= nil
end

return M
