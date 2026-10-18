local runtime_paths = {}
local path_ops = dofile((debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*)/[^/]+$") .. "/runtime_path_ops.lua")

local function _normalize_path(path)
  return path_ops.normalize(path)
end

local function _join_path(base, child)
  return path_ops.join(base, child)
end

local function _dirname(path)
  return path_ops.dirname(path)
end

local function _current_dir()
  return path_ops.current_dir()
end

local function _path_exists(path)
  return path_ops.path_exists(path)
end

local function _resolve_source_path(source_path, cwd)
  return path_ops.resolve_source_path(source_path, cwd)
end

local function _parent_dir(path)
  return path_ops.parent_dir(path)
end

local function _looks_like_repo_root(path)
  local required_entries = {
    "src",
    "test",
    "tools",
    "tools/cli.lua",
  }

  for _, entry in ipairs(required_entries) do
    if _path_exists(_join_path(path, entry)) ~= true then
      return false
    end
  end

  return true
end

function runtime_paths.resolve(opts)
  opts = opts or {}

  local cwd = _normalize_path(opts.cwd or _current_dir())
  local source_path = _resolve_source_path(
    opts.source_path or opts.script_path or opts.module_source or "",
    cwd
  )
  local script_dir = source_path
  if source_path:match("%.lua$") ~= nil then
    script_dir = _dirname(source_path)
  end

  local probe = script_dir
  while probe ~= "" do
    if _looks_like_repo_root(probe) then
      return {
        source_path = source_path,
        script_dir = script_dir,
        repo_root = probe,
        tools_dir = _join_path(probe, "tools"),
      }
    end

    local parent = _parent_dir(probe)
    if parent == probe or parent == "" then
      break
    end
    probe = parent
  end

  error("failed to resolve repo_root from source path: " .. tostring(source_path))
end

function runtime_paths.normalize_path(path)
  return _normalize_path(path)
end

function runtime_paths.join_path(base, child)
  return _join_path(base, child)
end

function runtime_paths.current_dir()
  return _current_dir()
end

return runtime_paths
