--- Load real busted and its dependencies exclusively from this project's tree.
local M = {}
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
local function cache_prefix(root)
  return root:gsub("\\", "/"):gsub("/+$", "") .. "/.toolcache/luarocks/"
end

-- Mutator alone supplies this pair, after creating an isolated worker. It grants
-- access to source rocks, never to source Lua files. Do not infer it from cwd.
local function absolute(path)
  local normalized = tostring(path):gsub("\\", "/"):gsub("/+$", "")
  assert(normalized:match("^%a:/") or normalized:match("^//[^/]+/[^/]+/"), "worker context requires absolute paths")
  for part in normalized:gmatch("[^/]+") do
    assert(part ~= "." and part ~= "..", "worker context forbids path traversal")
  end
  return normalized
end
local function within(path, base)
  return path:sub(1, #base + 1):lower() == base:lower() .. "/"
end
local function worker_context(root)
  local worker, source = os.getenv("MUTATOR_WORKER_ROOT"), os.getenv("MUTATOR_SOURCE_ROOT")
  if worker == nil and source == nil then return nil end
  assert(worker and worker ~= "" and source and source ~= "", "incomplete mutation worker context")
  worker, source = absolute(worker), absolute(source)
  assert(within(worker, source), "mutation worker outside source repository")
  local suffix = worker:sub(#source + 2)
  assert(suffix:match("^target/mutation%-workers/run%-[^/]+/worker%-[^/]+$"), "invalid mutation worker layout")
  -- A fresh nested runner has not installed the dependency searcher yet. Load
  -- the validator directly from the bound native cache without trusting preload
  -- or adding an unverified lfs object to package.loaded.
  local lfs = assert(package.loadlib(source .. "/.toolcache/luarocks/lib/lua/5.4/lfs.dll", "luaopen_lfs"))()
  assert(absolute(lfs.currentdir()):lower() == worker:lower(), "mutation worker cwd mismatch")
  assert(absolute(root):lower() == worker:lower(), "mutation worker root mismatch")
  -- Inspect each component: textual containment must not authorize junctions or
  -- symlinks escaping the physical source repository (or a linked cache).
  local function real_directory(path)
    local drive, tail = path:match("^(%a:/)(.*)$")
    if not drive then drive, tail = path:match("^(//[^/]+/[^/]+/)(.*)$") end
    local current = drive:gsub("/$", "")
    for part in tail:gmatch("[^/]+") do
      current = current .. "/" .. part
      assert(lfs.symlinkattributes(current, "mode") == "directory", "mutation worker requires real directories: " .. current)
    end
  end
  real_directory(worker)
  real_directory(source .. "/.toolcache/luarocks")
  assert(lfs.attributes(source .. "/.git", "mode"), "mutation source is not a source repository")
  for _, entry in ipairs({ "src", "test", "tools", "tools/cli.lua" }) do
    assert(lfs.attributes(source .. "/" .. entry, "mode"), "mutation source repository missing: " .. entry)
  end
  return { worker = worker, cache = source .. "/.toolcache/luarocks" }
end
local function worker_paths(context, bootstrap_paths)
  local function validate(paths)
    local kept = {}
    assert(paths ~= "" and not paths:match("^;") and not paths:match(";$") and not paths:find(";;", 1, true),
      "empty mutation worker search template")
    for template in paths:gmatch("[^;]+") do
      local normalized = absolute(template)
      local worker_cache = within(normalized, context.worker .. "/.toolcache")
      if bootstrap_paths and worker_cache then
        -- bootstrap prepends its own (empty) local rocks tree. Only those exact
        -- templates may be removed; unrelated foreign paths still fail closed.
        local relative = normalized:sub(#context.worker + 2)
        assert(relative == ".toolcache/luarocks/share/lua/5.4/?.lua"
          or relative == ".toolcache/luarocks/share/lua/5.4/?/init.lua"
          or relative == ".toolcache/luarocks/lib/lua/5.4/?.dll"
          or relative == ".toolcache/luarocks/lib/lua/5.4/?.so", "unexpected worker cache template: " .. template)
      else
        assert((within(normalized, context.worker) and not worker_cache) or within(normalized, context.cache),
          "search path outside mutation worker/cache: " .. template)
        kept[#kept + 1] = template
      end
    end
    return table.concat(kept, ";")
  end
  package.path, package.cpath = validate(package.path), validate(package.cpath)
end
-- Shared by bootstrap's worker-only read-only ensure and both loader entries.
-- Returning nil preserves the ordinary bootstrap/install contract.
function M.prepare_cache(root, bootstrap_paths)
  local context = worker_context(root)
  if context then worker_paths(context, bootstrap_paths) end
  return context and context.cache
end

-- Stock busted.runner (uml crap / mutate via .busted, #99) loads these before any
-- project code runs. Adopt them only inside the pinned uml environment: every
-- search template lies under the repo root (no user tree, no ;; default), and
-- every preloaded dependency resolves inside the project cache.
function M.adopt_preloaded(root)
  local repo = root:gsub("\\", "/"):gsub("/+$", "") .. "/"
  local cache = M.prepare_cache(root, false)
  local prefix = cache and cache .. "/" or cache_prefix(root)
  if not cache then
    for template in (package.path .. ";" .. package.cpath):gmatch("[^;]+") do
      local normalized = template:gsub("\\", "/")
      assert(normalized:sub(1, #repo) == repo, "search path outside repo root: " .. template)
    end
  end
  for name, object in pairs(package.loaded) do
    if dependency(name) and object and verified[name] ~= object then
      local source = package.searchpath(name, package.path) or package.searchpath(name, package.cpath)
      source = tostring(source):gsub("\\", "/")
      assert(source:sub(1, #prefix) == prefix, "dependency outside project cache: " .. name .. " " .. source)
      verified[name] = object
    end
  end
end
function M.install(root)
  local cache = M.prepare_cache(root, true)
  local prefix = cache and cache .. "/" or cache_prefix(root)
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
    assert(source, "cache dependency missing: " .. name)
    source = source:gsub("\\", "/")
    assert(source:sub(1, #prefix) == prefix, "dependency outside project cache: " .. name .. " " .. source)
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
