--- Stock busted.runner adapter for test/helper.lua (#99): crapper / mutator call
--- busted.runner directly from .busted, bypassing tools/packages/test_runner.
--- Mirrors busted_backend's project events so the helper's lifecycle contract
--- (RNG reseed before the before_each chain, baseline-leak guard after
--- after_each, leaks fail the run) holds under the stock runner too.
return function(busted, _, helper_options)
  -- busted reads .busted from the cwd, so the cwd is the repo root. Adopt the
  -- runner's preloads before test.bootstrap widens package.path (tools/ is not
  -- on the pinned path yet, so register the loader under its module name).
  local cache_loader = dofile("tools/packages/test_runner/cache_loader.lua")
  package.loaded["packages.test_runner.cache_loader"] = cache_loader
  local root = require("lfs").currentdir():gsub("\\", "/"):gsub("/+$", "") .. "/"
  cache_loader.adopt_preloaded(root)
  -- Resolve bootstrap from worker source before it adds tools/test templates.
  -- install revalidates the worker/source binding and confines paths to the
  -- worker plus the controlled Lua environment.
  if os.getenv("MUTATOR_WORKER_ROOT") ~= nil or os.getenv("MUTATOR_SOURCE_ROOT") ~= nil then
    require("test.bootstrap").install_package_paths()
    cache_loader.install(root)
  end

  -- crapper's luacov config drops absolute chunk names (^%a:), but test.bootstrap
  -- puts the repo root on package.path as an absolute path. Every repo-local Lua
  -- file (outside the controlled Lua environment) is therefore loaded under its
  -- relative forward-slash name (tools/foundation derives sibling paths from it).
  local function canonical(path)
    local normalized = tostring(path):gsub("\\", "/"):gsub("^%./", "")
    if normalized:sub(1, #root):lower() == root:lower() then normalized = normalized:sub(#root + 1) end
    if normalized:match("^%.%./") then return nil end
    local collapsed
    repeat
      collapsed = normalized
      normalized = normalized:gsub("[^/]+/%.%./", "", 1):gsub("/%./", "/")
    until normalized == collapsed
    if normalized:match("^%.%./") or normalized:match("^%a:") or normalized:match("^/") then return nil end
    return normalized
  end
  -- Specs swap or drop globals (package, io, assert ...); hold the originals.
  local package_lib, io_open, load_chunk, raise = package, io.open, load, error
  local original_loadfile, original_dofile = loadfile, dofile
  local function load_canonical(path, mode, ...)
    local name = canonical(path)
    local file = name and io_open(path, "rb")
    if not file then return nil end
    local text = file:read("a"):gsub("^#[^\n]*", "", 1)
    file:close()
    return load_chunk(text, "@" .. name, mode or "bt", ...)
  end
  local function canonical_loadfile(path, ...)
    if path == nil then return original_loadfile(path, ...) end
    local chunk, err = load_canonical(path, ...)
    if chunk == nil and err == nil then return original_loadfile(path, ...) end
    return chunk, err
  end
  _G.loadfile = canonical_loadfile
  _G.dofile = function(path)
    if path == nil then return original_dofile() end
    local chunk, err = canonical_loadfile(path)
    if chunk == nil then raise(err, 2) end
    return chunk()
  end
  table.insert(package_lib.searchers, 2, function(name)
    local path = package_lib.searchpath(name, package_lib.path)
    if path == nil or canonical(path) == nil then return nil end
    local chunk, err = load_canonical(path)
    if chunk == nil then raise(err, 0) end
    return chunk, path
  end)
  -- luacov's untested-file walk names files with the native separator
  -- (src\ui\x.lua) while the C hook records chunk names verbatim; store stats
  -- under the walk's names so one source never shows up as two LCOV records.
  local stats = package.loaded["luacov.stats"]
  if stats then
    local save, update = stats.save, package.loaded["luacov.runner"].update_stats
    stats.save = function(statsfile, data)
      local native = {}
      for name, file_data in pairs(data) do
        local key = name:gsub("/", "\\")
        if native[key] then update(native[key], file_data) else native[key] = file_data end
      end
      return save(statsfile, native)
    end
  end

  -- The stock runner owns `it`'s executor in a private table; swap the genuine
  -- executor in place (no second register, which would attach every it twice).
  local executors
  for index = 1, math.huge do
    local name, value = debug.getupvalue(busted.execute, index)
    if name == nil then break end
    if name == "executors" then executors = value break end
  end
  local real_it = assert(executors and executors.it, "busted executors table unavailable")

  local function element(test)
    local names = { test.name }
    local parent = busted.context.parent(test)
    while parent and parent.descriptor ~= "file" do
      if parent.name then table.insert(names, 1, parent.name) end
      parent = busted.context.parent(parent)
    end
    local trace = {}
    for key, value in pairs(test.trace or {}) do trace[key] = value end
    local file = busted.getFile(test)
    if file then trace.source = "@" .. file.name end
    return { name = test.name, full_name = table.concat(names, " "), trace = trace }
  end

  executors.it = function(test)
    local project_element = element(test)
    busted.publish({ "project", "case", "start" }, project_element, nil)
    real_it(test)
    busted.publish({ "project", "case", "end" }, project_element, nil)
  end

  local counts = { errors = 0 }
  local options = { arguments = helper_options.arguments, busted = busted, counts = counts }
  assert(loadfile("test/helper.lua"))(options)

  busted.subscribe({ "suite", "end" }, function()
    busted.publish({ "project", "suite", "end" })
    if counts.errors > 0 then
      busted.publish({ "error" }, busted.context.get(), nil,
        counts.errors .. " shared runtime baseline leak(s); see # BASELINE LEAK lines")
    end
    return nil, true
  end)
  return true
end
