local M = {}

-- 递归枚举 root 下的 .lua 文件。`find -print0` 保证空格/中文/换行文件名原样读回;
-- 目录缺失时 find 非零,由调用方报 "no lua files found"。
local function _build_list_command(root)
  return "find " .. ("'" .. tostring(root):gsub("/", "/"):gsub("'", "'\\''") .. "'")
    .. " -type f -name '*.lua' -print0 2>/dev/null"
end

local function _is_file_path(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

function M.path_exists(path)
  if _is_file_path(path) then
    return true
  end
  local ok = os.rename(path, path)
  if ok then
    return true
  end
  return false
end

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

  local process = io.popen(_build_list_command(root))
  if not process then
    return nil, "cannot run list command for root: " .. tostring(root)
  end

  local files = {}
  local raw = process:read("*a") or ""
  for line in (raw .. "\0"):gmatch("(.-)\0") do
    if line ~= "" then
      files[#files + 1] = M.normalize_path(line)
    end
  end

  local ok = process:close()
  if ok == nil or ok == false then
    return nil, "list command failed for root: " .. tostring(root)
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
