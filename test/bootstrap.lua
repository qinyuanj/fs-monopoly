local M = {}

local _package_paths_installed = false

local function _normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function _module_dir()
  local source = debug.getinfo(1, "S").source or "@test/bootstrap.lua"
  local normalized = _normalize_path(source):gsub("^@", "")
  return normalized:match("^(.*)/[^/]+$") or "test"
end

function M.install_package_paths()
  if _package_paths_installed then
    return
  end

  local bootstrap = dofile(_module_dir() .. "/../tools/foundation/bootstrap.lua")
  bootstrap.install(debug.getinfo(1, "S").source)

  _package_paths_installed = true
end

function M.dofile_first(paths)
  for _, path in ipairs(paths or {}) do
    local file = io.open(path, "r")
    if file then
      file:close()
      return dofile(path)
    end
  end
  error("missing script: " .. table.concat(paths or {}, ", "))
end

function M.load_modules(module_names)
  local modules = {}
  for _, module_name in ipairs(module_names or {}) do
    modules[#modules + 1] = require(module_name)
  end
  return modules
end

M.install_package_paths()

return M
