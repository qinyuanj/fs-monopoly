require("test.bootstrap").install_package_paths()
local loader = require("packages.test_runner.cache_loader")
local root = require("test.support.luassert_loader").repo_root()
local lua_env = dofile("tools/foundation/lua_env.lua")
local roots = lua_env.roots()
lua_env.install_paths(roots)
local mode = arg[1]

local function pinned_paths()
  local paths = { root .. "/?.lua", root .. "/?/init.lua" }
  for _, tree in ipairs(roots) do
    local base = tree:gsub("\\", "/"):gsub("/+$", "")
    paths[#paths + 1] = base .. "/share/lua/5.4/?.lua"
    paths[#paths + 1] = base .. "/share/lua/5.4/?/init.lua"
  end
  return table.concat(paths, ";")
end

local function pinned_cpaths()
  local paths = {}
  for _, tree in ipairs(roots) do
    local base = tree:gsub("\\", "/"):gsub("/+$", "")
    paths[#paths + 1] = base .. "/lib/lua/5.4/?.dll"
    paths[#paths + 1] = base .. "/lib/lua/5.4/?.so"
  end
  return table.concat(paths, ";")
end

if mode == "uninstalled" then
  assert(loader.verified_module("luassert") == nil)
elseif mode == "adopted" then
  -- 插件 busted 子进程的形态:busted 先于项目代码装载,helper 登记它装载的依赖身份。
  package.path = pinned_paths()
  package.cpath = pinned_cpaths()
  require("busted.core")()
  require("busted")
  local object = require("luassert")
  loader.adopt_preloaded()
  assert(loader.verified_module("luassert") == object)
  require("test.support.scenario_suites.shared.helpers")
elseif mode == "injected" then
  package.loaded.luassert = {}
  require("test.support.scenario_suites.shared.helpers")
else
  loader.install()
  require("busted.core")()
  require("busted")
  local object = require("luassert")
  require("luassert.spy")
  if mode == "replaced" then
    package.loaded["luassert.spy"] = {}
    require("test.support.scenario_suites.shared.helpers")
  else
    assert(loader.verified_module("luassert") == object)
    assert(loader.verified_module("unknown") == nil)
    require("test.support.scenario_suites.shared.helpers")
  end
end
