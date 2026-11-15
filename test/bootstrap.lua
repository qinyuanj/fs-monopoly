local M = {}

local _package_paths_installed = false

-- 本文件是「第一块砖的加载者」:它必须把 foundation.bootstrap 拉进来,而此刻
-- package.path 里还没有 tools/,所以只能按自身位置 dofile —— 这一处自定位是
-- 结构决定的,不是懒得迁移。位置取一次,后续 install 也用同一份。
local _self = debug.getinfo(1, "S").source or "@test/bootstrap.lua"

function M.install_package_paths()
  if _package_paths_installed then
    return
  end

  local dir = _self:gsub("\\", "/"):gsub("^@", ""):match("^(.*)/[^/]+$") or "test"
  dofile(dir .. "/../tools/foundation/bootstrap.lua").install(_self)

  _package_paths_installed = true
end

M.install_package_paths()

return M
