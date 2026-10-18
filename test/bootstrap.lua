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

M.install_package_paths()

return M
