---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/uml_quality/test/test_uml_quality_busted.lua") end
require("test.bootstrap").install_package_paths()

-- 仓根 .busted + test/busted_helper.lua(#99):crapper / mutator 直接调原版
-- busted.runner。子进程按 uml 钉死环境装 package.path(仅仓根 + 受控 Lua 环境
-- 的 tree),只跑 test/fixtures/stock_busted 下的样本,不跑整套。
local check = require("luassert")
local proc = require("foundation.proc")
local lua54 = require("foundation.lua54")
local fs = require("foundation.fs")
local env = require("foundation.env")
local runtime = require("packages.uml_quality.runtime")
local lua_env = require("foundation.lua_env")
local root = require("foundation.bootstrap").resolve(debug.getinfo(1, "S").source).repo_root:gsub("\\", "/")
local controlled = lua_env.roots()

local function _paths(prefix, extra)
  local paths = { prefix .. "/?.lua", prefix .. "/?/init.lua" }
  for _, tree in ipairs(controlled) do
    local base = tree:gsub("\\", "/"):gsub("/+$", "")
    paths[#paths + 1] = base .. "/share/lua/5.4/?.lua"
    paths[#paths + 1] = base .. "/share/lua/5.4/?/init.lua"
  end
  if extra then paths[#paths + 1] = extra end
  return table.concat(paths, ";")
end

local function _cpaths()
  local paths = {}
  for _, tree in ipairs(controlled) do
    local base = tree:gsub("\\", "/"):gsub("/+$", "")
    paths[#paths + 1] = base .. "/lib/lua/5.4/?.so"
  end
  return table.concat(paths, ";")
end

local function _stock_busted(spec)
  local pinned = "package.path = " .. string.format("%q", _paths(root))
    .. "; package.cpath = " .. string.format("%q", _cpaths())
  return proc.run_command({ lua54.lua54_bin(), "-e",
    pinned .. "; require('busted.runner')({ standalone = false }); os.exit(0)",
    "--", "busted", "--ignore-lua", spec }, { cwd = root })
end

describe("uml quality stock busted adapter", function()

it("runs specs through test/helper.lua with project events and relative chunk names", function()
  local result = _stock_busted("test/fixtures/stock_busted/test_adapter.lua")
  check.equal(0, result.code, result.output)
  check.truthy(result.output:find("1..2", 1, true), result.output)
end)

it("keeps a failing assertion failing", function()
  local result = _stock_busted("test/fixtures/stock_busted/test_failing.lua")
  check.equal(1, result.code, result.output)
  check.truthy(result.output:find("not ok 1", 1, true), result.output)
end)

-- Worker fixtures copy tracked source only. The controlled Lua environment is
-- shared read-only by path, never copied or linked into the worker.
local worker, run_root
local function worker_probe(body, options)
  options = options or {}
  local script = "package.path=" .. string.format("%q", _paths(worker, options.path))
    .. ";package.cpath=" .. string.format("%q", _cpaths())
    .. ";" .. body
  local launch = env.make_temp_path("worker_env_probe", ".sh")
  local text = runtime.launch_text(options.cwd or worker, {
    { "MUTATOR_WORKER_ROOT", options.worker_root or worker },
    { "MUTATOR_SOURCE_ROOT", options.source_root or root },
    { "LUA54_BIN", lua54.lua54_bin() },
  }, { lua54.lua54_bin(), "-e", script })
  check.truthy(fs.write_file(launch, text))
  local result = proc.run_command({ "sh", launch })
  fs.remove_path(launch)
  return result
end
local adopt = "local loader=dofile('tools/packages/test_runner/cache_loader.lua');"
  .. "require('busted.core')();require('busted');loader.adopt_preloaded(require('lfs').currentdir());"

describe("mutation worker source and controlled environment binding", function()
  setup(function()
    run_root = root .. "/target/mutation-workers/run-consumer-" .. tostring(os.time())
    worker = run_root .. "/worker-env-test"
    check.truthy(fs.ensure_dir(worker))
    for _, directory in ipairs({ "src", "test", "tools" }) do
      local result = proc.run_command({ "git", "ls-files", directory }, { cwd = root })
      check.equal(0, result.code, result.output)
      for file in result.output:gmatch("[^\r\n]+") do
        check.truthy(fs.copy_file(root .. "/" .. file, worker .. "/" .. file))
      end
    end
    -- Keep the real helper/options, replace only the full-suite default roots.
    local config = assert(fs.read_raw(root .. "/.busted")):gsub('ROOT = { "test/behavior", "test/contract" }', 'ROOT = {}')
    check.truthy(fs.write_file(worker .. "/.busted", config))
  end)
  teardown(function() if run_root then fs.remove_path(run_root) end end)

  it("adopts real stock preloads and preserves binding on subsequent install", function()
    local result = worker_probe(adopt .. "loader.install(require('lfs').currentdir());"
      .. "package.loaded['luassert.spy']=nil;assert(require('luassert.spy'));"
      .. "print('WORKER_ENV_BOUND')")
    check.equal(0, result.code, result.output)
    check.matches("WORKER_ENV_BOUND", result.output, 1, true)
  end)

  it("runs the stock helper with worker source and controlled environment after bootstrap", function()
    local fixture = worker .. "/test/fixtures/stock_busted/test_worker_binding.lua"
    check.truthy(fs.write_file(worker .. "/src/worker_env_probe.lua", "return { marker = 'worker-only-bytes' }\n"))
    check.truthy(fs.write_file(fixture, [[
local check = require('luassert')
describe('worker binding', function()
  it('keeps worker source and controlled environment separate', function()
    local worker = os.getenv('MUTATOR_WORKER_ROOT'):gsub('\\', '/')
    local function resolved(name, path) return assert(package.searchpath(name, path)):gsub('\\', '/') end
    local lua_env = dofile('tools/foundation/lua_env.lua')
    local roots = lua_env.roots()
    check.equal(worker .. '/test/bootstrap.lua', resolved('test.bootstrap', package.path))
    check.equal('worker-only-bytes', require('src.worker_env_probe').marker)
    check.equal('@tools/foundation/fs.lua', debug.getinfo(require('foundation.fs').read_raw, 'S').source)
    check.is_true(lua_env.is_inside(resolved('luassert', package.path), roots))
    check.is_nil(resolved('luassert', package.path):find(worker, 1, true))
    local loader = require('packages.test_runner.cache_loader')
    dofile('tools/foundation/bootstrap.lua').install('test/helper.lua')
    loader.install(worker)
    package.loaded['luassert.spy'] = nil
    check.truthy(require('luassert.spy'))
    local rocks_loader = package.searchpath('luarocks.loader', package.path)
    check.is_true(rocks_loader == nil or lua_env.is_inside(rocks_loader, roots))
  end)
end)
]]))
    -- Pass just this fixture via arg: the helper still comes from the real .busted.
    local result = worker_probe("arg={'--ignore-lua','test/fixtures/stock_busted/test_worker_binding.lua'};"
      .. "require('busted.runner')({standalone=false})")
    check.equal(0, result.code, result.output)
    check.matches("ok 1", result.output, 1, true)
    check.matches("1..1", result.output, 1, true)
  end)

  it("runs a real nested project runner without installing a worker environment", function()
    check.truthy(fs.write_file(worker .. "/test/fixtures/stock_busted/test_worker_runner.lua", [[
describe('nested worker source', function()
  it('uses worker bytes and the controlled environment', function()
    local worker = os.getenv('MUTATOR_WORKER_ROOT'):gsub('\\', '/')
    local lua_env = dofile('tools/foundation/lua_env.lua')
    local roots = lua_env.roots()
    assert.are.equal('nested-worker-bytes', require('src.nested_worker_probe').marker)
    assert.are.equal(worker .. '/src/nested_worker_probe.lua', package.searchpath('src.nested_worker_probe', package.path):gsub('\\', '/'))
    assert.truthy(lua_env.is_inside(package.searchpath('busted.runner', package.path), roots))
  end)
end)
]]))
    check.truthy(fs.write_file(worker .. "/src/nested_worker_probe.lua", "return {marker='nested-worker-bytes'}\n"))
    local result = worker_probe("arg={'--output=TAP','--helper=test/helper.lua','--','test/fixtures/stock_busted/test_worker_runner.lua'};"
      .. "dofile('tools/packages/test_runner/runner.lua')")
    check.equal(0, result.code, result.output)
    check.matches("cases=1 passed=1 failed=0 errors=0", result.output, 1, true)
  end)

  it("rejects source code fallback, foreign trees, traversal and empty templates", function()
    for _, path in ipairs({ root .. "/?.lua", "C:/elsewhere/?.lua", "C:/foreign-tree/share/lua/5.4/?.lua",
      worker .. "/../?.lua", root .. "/target/../../?.lua", ";;" }) do
      local result = worker_probe(adopt, { path = path })
      check.equal(1, result.code, path .. "\n" .. result.output)
    end
  end)

  it("rejects forged worker roots, mismatched cwd, and incomplete context", function()
    for _, options in ipairs({ { worker_root = root }, { cwd = root }, { source_root = worker },
      { worker_root = worker .. "/../worker-env-test" }, { source_root = "" }, { worker_root = "" } }) do
      local result = worker_probe("local loader=dofile('tools/packages/test_runner/cache_loader.lua');"
        .. "loader.adopt_preloaded(require('lfs').currentdir())", options)
      check.equal(1, result.code, result.output)
    end
  end)

  it("does not turn failing worker assertions into a passing baseline", function()
    local result = worker_probe("arg={'--ignore-lua','test/fixtures/stock_busted/test_failing.lua'};"
      .. "require('busted.runner')({standalone=false})")
    check.equal(1, result.code, result.output)
    check.matches("not ok 1", result.output, 1, true)
  end)
end)

end)
