--- Load real busted and its dependencies exclusively from the controlled Lua
--- environment (GLOSSARY「受控 Lua 环境」,spec #146 / #151).
---
--- The reference is the machine LuaRocks tree root resolved through `luarocks
--- config rocks_trees`, never a repository-local cache. Every dependency must resolve
--- inside one of those roots (C modules included); a preloaded module of unknown
--- provenance fails closed.
local M = {}

local function _module_dir()
  local source = debug.getinfo(1, "S").source or "@tools/packages/test_runner/cache_loader.lua"
  return tostring(source):gsub("\\", "/"):gsub("^@", ""):match("^(.*)/[^/]+$")
    or "tools/packages/test_runner"
end

-- 本文件会被 .busted 的 helper 在 test.bootstrap 拓宽 package.path 之前 dofile,
-- 所以按相对路径加载 foundation,不 require。路径先折叠 `..` 段:同一个文件
-- 只允许有一个 chunk 名,否则覆盖率会记成两个 LCOV 源。
local function _normalize(path)
  local normalized = tostring(path or ""):gsub("\\", "/")
  local parts = {}
  for segment in normalized:gmatch("[^/]+") do
    if segment == ".." then
      if #parts > 0 then parts[#parts] = nil end
    elseif segment ~= "." then
      parts[#parts + 1] = segment
    end
  end
  local prefix = normalized:sub(1, 1) == "/" and "/" or ""
  return prefix .. table.concat(parts, "/")
end

local lua_env = dofile(_normalize(_module_dir() .. "/../../foundation/lua_env.lua"))

local prefixes = { "busted", "luassert", "say", "cliargs", "mediator", "pl", "term", "system", "lfs", "dkjson", "datafile" }
local verified = {}

local function dependency(name)
  for _, prefix in ipairs(prefixes) do
    if name == prefix or name:sub(1, #prefix + 1) == prefix .. "." then return true end
  end
  return false
end

function M.verified_module(name)
  for dependency_name, object in pairs(verified) do
    assert(package.loaded[dependency_name] == object, "verified module identity changed: " .. dependency_name)
  end
  return verified[name]
end

local _roots
-- 受控 Lua 环境的 tree 根;进程内解析一次。
function M.roots()
  if _roots == nil then
    local roots, err = lua_env.roots()
    assert(roots, err)
    _roots = roots
  end
  return _roots
end

-- Stock busted.runner (plugin uml_crap / uml_mutate via .busted, #99) loads its
-- dependencies before any project code runs. The plugin owns that process's Lua
-- environment (ADR 0082): record what it loaded as the verified identities that
-- test/support reads through verified_module, without re-judging its search path.
function M.adopt_preloaded()
  for name, object in pairs(package.loaded) do
    if dependency(name) and object and verified[name] == nil then
      verified[name] = object
    end
  end
end

function M.install()
  local roots = M.roots()
  for name, object in pairs(package.loaded) do
    if dependency(name) and object and verified[name] ~= object then
      error("unverified preloaded module: " .. name, 0)
    end
  end
  local function searcher(name)
    if not dependency(name) then return nil end
    local source = package.searchpath(name, package.path)
    local native = false
    if not source then source = package.searchpath(name, package.cpath); native = true end
    assert(source, "controlled dependency missing: " .. name)
    source = source:gsub("\\", "/")
    assert(lua_env.is_inside(source, roots),
      "dependency outside controlled Lua environment: " .. name .. " " .. source)
    local chunk, err
    if native then chunk, err = package.loadlib(source, "luaopen_" .. name:gsub("%.", "_"))
    else chunk, err = loadfile(source) end
    assert(chunk, err)
    return function(...)
      local object = chunk(...)
      verified[name] = object == nil and true or object
      return object
    end, source
  end
  table.insert(package.searchers, 1, searcher)
end

return M
