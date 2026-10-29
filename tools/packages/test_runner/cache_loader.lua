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

local function absolute(path)
  local normalized = tostring(path):gsub("\\", "/"):gsub("/+$", "")
  assert(normalized:sub(1, 1) == "/", "worker context requires absolute paths")
  for part in normalized:gmatch("[^/]+") do
    assert(part ~= "." and part ~= "..", "worker context forbids path traversal")
  end
  return normalized
end

-- 按字节比较(ADR 0073):两侧都取自同一来源(MUTATOR_* 与磁盘路径),macOS 保留大小写,
-- 不需要大小写折叠。
local function within(path, base)
  return path:sub(1, #base + 1) == base .. "/"
end

-- 只认 POSIX 根 "/" 起头的绝对路径(ADR 0073)。
local function _real_directory(lfs, path)
  local tail = path:match("^/(.*)$")
  assert(tail ~= nil, "worker context requires an absolute path: " .. tostring(path))
  local current = ""
  for part in tail:gmatch("[^/]+") do
    current = current .. "/" .. part
    assert(lfs.symlinkattributes(current, "mode") == "directory", "worker requires real directories: " .. current)
  end
end

-- Load the validator C module from the controlled tree itself. A fresh nested
-- runner has not installed the dependency searcher yet, so resolve `lfs` against
-- the controlled roots' cpath templates explicitly instead of trusting preload.
local function _controlled_lfs(roots)
  local search = {}
  for _, root in ipairs(roots) do
    local base = tostring(root):gsub("\\", "/"):gsub("/+$", "")
    search[#search + 1] = base .. "/lib/lua/5.4/?.so"
  end
  local file, err = lua_env.locate("lfs", roots, table.concat(search, ";"))
  assert(file, err)
  return assert(package.loadlib(file, "luaopen_lfs"))()
end

-- Mutator alone supplies this pair, after creating an isolated worker. It grants
-- access to source rocks, never to source Lua files. Do not infer it from cwd.
local function worker_context(root)
  local worker, source = os.getenv("MUTATOR_WORKER_ROOT"), os.getenv("MUTATOR_SOURCE_ROOT")
  if worker == nil and source == nil then return nil end
  assert(worker and worker ~= "" and source and source ~= "", "incomplete mutation worker context")
  worker, source = absolute(worker), absolute(source)
  assert(within(worker, source), "mutation worker outside source repository")
  local suffix = worker:sub(#source + 2)
  assert(suffix:match("^target/mutation%-workers/run%-[^/]+/worker%-[^/]+$"), "invalid mutation worker layout")

  local roots = M.roots()
  local lfs = _controlled_lfs(roots)
  assert(absolute(lfs.currentdir()) == worker, "mutation worker cwd mismatch")
  assert(absolute(root) == worker, "mutation worker root mismatch")
  -- Inspect each component: textual containment must not authorize junctions or
  -- symlinks escaping the physical source repository (or a linked tree).
  _real_directory(lfs, worker)
  for _, controlled in ipairs(roots) do
    _real_directory(lfs, tostring(controlled):gsub("\\", "/"):gsub("/+$", ""))
  end
  assert(lfs.attributes(source .. "/.git", "mode"), "mutation source is not a source repository")
  for _, entry in ipairs({ "src", "test", "tools", "tools/cli.lua" }) do
    assert(lfs.attributes(source .. "/" .. entry, "mode"), "mutation source repository missing: " .. entry)
  end
  return { worker = worker, source = source, roots = roots }
end

local function _is_controlled_template(template, roots)
  local normalized = template:gsub("\\", "/")
  local probe = normalized:gsub("%?.*$", "x")
  if not lua_env.is_inside(probe, roots) then return false end
  return normalized:match("^.*/share/lua/5%.4/[^;]*$") ~= nil
    or normalized:match("^.*/lib/lua/5%.4/[^;]*$") ~= nil
end

local function worker_paths(context)
  local function validate(paths)
    local kept = {}
    assert(paths ~= "" and not paths:match("^;") and not paths:match(";$") and not paths:find(";;", 1, true),
      "empty mutation worker search template")
    for template in paths:gmatch("[^;]+") do
      local normalized = absolute(template)
      local in_worker = within(normalized, context.worker)
      local controlled = _is_controlled_template(normalized, context.roots)
      assert(in_worker or controlled,
        "search path outside mutation worker/controlled environment: " .. template)
      kept[#kept + 1] = template
    end
    return table.concat(kept, ";")
  end
  package.path, package.cpath = validate(package.path), validate(package.cpath)
end

-- Validate the mutation worker/source binding and confine the search paths to
-- the worker plus the controlled Lua environment. Returns nil outside a worker.
function M.prepare_worker(root)
  local context = worker_context(root)
  if context then worker_paths(context) end
  return context
end

local function _assert_templates(search, context, repo_prefix, roots)
  assert(search ~= "" and not search:match("^;") and not search:match(";$") and not search:find(";;", 1, true),
    "empty dependency search template")
  for template in search:gmatch("[^;]+") do
    local normalized = template:gsub("\\", "/")
    local inside_repo = repo_prefix ~= nil and normalized:sub(1, #repo_prefix) == repo_prefix
    local inside_worker = context ~= nil and within(normalized, context.worker)
    assert(inside_repo or inside_worker or _is_controlled_template(normalized, roots),
      "search path outside repo root/controlled environment: " .. template)
  end
end

-- Stock busted.runner (uml crap / mutate via .busted, #99) loads these before any
-- project code runs. Adopt them only inside the pinned environment: every search
-- template lies under the repo root (or the mutation worker) plus the controlled
-- Lua environment, and every preloaded dependency resolves inside those roots.
function M.adopt_preloaded(root)
  local repo = root:gsub("\\", "/"):gsub("/+$", "") .. "/"
  local context = M.prepare_worker(root)
  local roots = context and context.roots or M.roots()
  _assert_templates(package.path, context, repo, roots)
  _assert_templates(package.cpath, context, repo, roots)
  for name, object in pairs(package.loaded) do
    if dependency(name) and object and verified[name] ~= object then
      local source = package.searchpath(name, package.path) or package.searchpath(name, package.cpath)
      source = tostring(source):gsub("\\", "/")
      assert(lua_env.is_inside(source, roots),
        "dependency outside controlled Lua environment: " .. name .. " " .. source)
      verified[name] = object
    end
  end
end

function M.install(root)
  local context = M.prepare_worker(root)
  local roots = context and context.roots or M.roots()
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
