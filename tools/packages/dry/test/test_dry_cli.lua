---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/dry/test/test_dry_cli.lua") end

require("test.bootstrap").install_package_paths()

-- dry 子命令(#148 / 父 spec #146)。结构重复检测由邻接 .uml-viewer/dryer 承接。
--
-- 上半部分注入 proc/fs 替身,断言三态判据与「运行前移走旧 dry.edn、失败时放回」;
-- 下半部分真实起进程:缺检出报「不可用」,检出就绪时在原生 Windows 上真扫夹具。
-- 旧失败形态是「空扫描假绿」,所以每个正例都要求本次新写出 dry.edn,而不只看退出码。
local check = require("luassert")
local cli = require("packages.dry.cli")
local dryer = require("packages.dry.dryer")
local env_lib = require("foundation.env")
local fs_lib = require("foundation.fs")
local proc_lib = require("foundation.proc")

local ROOT = "C:/fake"
local PYTHON = dryer.python_path(ROOT)

local function _capture(fn)
  local out, err = {}, {}
  -- rawset：直接赋值全局 io 的字段会触发 luacheck W122。
  local real_out, real_err, real_write = io.stdout, io.stderr, io.write
  local function sink(list)
    return setmetatable({}, { __index = function(_, key)
      if key == "write" then
        return function(self, ...) for _, v in ipairs({ ... }) do list[#list + 1] = tostring(v) end return self end
      end
      return function() end
    end })
  end
  rawset(io, "stdout", sink(out))
  rawset(io, "stderr", sink(err))
  rawset(io, "write", function(...) for _, v in ipairs({ ... }) do out[#out + 1] = tostring(v) end end)
  local ok, result = pcall(fn)
  rawset(io, "stdout", real_out)
  rawset(io, "stderr", real_err)
  rawset(io, "write", real_write)
  assert(ok, result)
  return result, table.concat(out), table.concat(err)
end

-- 假文件系统:files 记录存在的路径 -> 内容;copy/remove 真改这张表。
local function _fake_fs(files)
  local fs = { files = files }
  function fs.path_exists(path) return files[path] ~= nil end
  function fs.remove_path(path) files[path] = nil return true end
  function fs.copy_file(from, to) files[to] = files[from] return files[from] ~= nil end
  return fs
end

local function _fake_proc(handlers)
  local proc = { calls = {} }
  function proc.run_command(argv, options)
    proc.calls[#proc.calls + 1] = { argv = argv, cwd = options and options.cwd }
    return handlers(argv, options, proc)
  end
  return proc
end

local function _ready_fs(extra)
  local files = { [dryer.checkout_dir(ROOT) .. "/pyproject.toml"] = "x", [PYTHON] = "py" }
  for key, value in pairs(extra or {}) do files[key] = value end
  return _fake_fs(files)
end

local PROBE_OK = { ok = true, code = 0, output = "3.12.10\n" .. dryer.checkout_dir(ROOT) .. "/src/dryer/__init__.py\n" }

describe("dry cli", function()

it("help describes dryer, the effective-result rule and the unavailable code", function()
  local code, out = _capture(function() return cli.main({ "--help" }, {}) end)

  check.same(0, code)
  check.truthy(out:find("dryer", 1, true) ~= nil, out)
  check.truthy(out:find(".metrics/dry.edn", 1, true) ~= nil, out)
  check.truthy(out:find("status=unavailable", 1, true) ~= nil, out)
  check.is_nil(out:find("dry4lua", 1, true), out)
end)

describe("injected environment", function()

it("reports unavailable and starts nothing when the checkout is missing", function()
  local proc = _fake_proc(function() error("tool must not start") end)
  local code, _, err = _capture(function()
    return cli.main({ "src" }, { root = ROOT, proc = proc, fs = _fake_fs({}) })
  end)

  check.same(3, code)
  check.truthy(err:find("status=unavailable tool=dryer step=checkout", 1, true) ~= nil, err)
  check.same(0, #proc.calls)
end)

it("reports unavailable and starts nothing when the venv is missing", function()
  local proc = _fake_proc(function() error("tool must not start") end)
  local files = { [dryer.checkout_dir(ROOT) .. "/pyproject.toml"] = "x" }
  local code, _, err = _capture(function()
    return cli.main({ "src" }, { root = ROOT, proc = proc, fs = _fake_fs(files) })
  end)

  check.same(3, code)
  check.truthy(err:find("status=unavailable tool=dryer step=venv", 1, true) ~= nil, err)
  check.same(0, #proc.calls)
end)

-- venv 里的包不是出自邻接检出(例如全局 pip 装的 dryer):真实失败,不是不可用。
it("fails, not unavailable, when dryer imports from outside the checkout", function()
  local proc = _fake_proc(function()
    return { ok = true, code = 0, output = "3.12.10\nC:/elsewhere/site-packages/dryer/__init__.py\n" }
  end)
  local code, _, err = _capture(function()
    return cli.main({ "src" }, { root = ROOT, proc = proc, fs = _ready_fs() })
  end)

  check.same(1, code)
  check.truthy(err:find("expected under", 1, true) ~= nil, err)
  check.is_nil(err:find("status=unavailable", 1, true), err)
  check.same(1, #proc.calls)
end)

it("runs the venv python directly with the user's args and passes on a fresh metrics file", function()
  local fs = _ready_fs({ [ROOT .. "/.metrics/dry.edn"] = "OLD" })
  local proc = _fake_proc(function(argv)
    if argv[#argv - 1] == "-c" then return PROBE_OK end
    fs.files[ROOT .. "/.metrics/dry.edn"] = "NEW"
    return { ok = true, code = 0, output = "DUPLICATE score=1.00\n  a:1-2\n  b:3-4\n" }
  end)
  local code, out = _capture(function()
    return cli.main({ "--threshold", "0.9", "src" }, { root = ROOT, proc = proc, fs = fs })
  end)

  check.same(0, code, out)
  check.truthy(out:find("DUPLICATE score=1.00", 1, true) ~= nil, out)
  check.same({ PYTHON, "-I", "-m", "dryer", "--threshold", "0.9", "src" }, proc.calls[2].argv)
  check.equal(ROOT, proc.calls[2].cwd)
  check.equal("NEW", fs.files[ROOT .. "/.metrics/dry.edn"])
end)

-- 重复项只提示、不致失败:有 DUPLICATE 行仍退 0,没有也退 0。
it("exits 0 when duplicates are reported", function()
  local fs = _ready_fs()
  local proc = _fake_proc(function(argv)
    if argv[#argv - 1] == "-c" then return PROBE_OK end
    fs.files[ROOT .. "/.metrics/dry.edn"] = "{:candidates []}"
    return { ok = true, code = 0, output = "DUPLICATE score=0.95\n" }
  end)

  check.same(0, (_capture(function() return cli.main({}, { root = ROOT, proc = proc, fs = fs }) end)))
end)

-- 零候选文件:dryer 退 0 但不写文件。必须退 1 点名原因,且入库的旧 dry.edn 原样放回。
it("fails on zero candidate files and restores the committed metrics file", function()
  local fs = _ready_fs({ [ROOT .. "/.metrics/dry.edn"] = "COMMITTED" })
  local proc = _fake_proc(function(argv)
    if argv[#argv - 1] == "-c" then return PROBE_OK end
    return { ok = true, code = 0, output = dryer.NO_SOURCE_MESSAGE .. "\n" }
  end)
  local code, _, err = _capture(function()
    return cli.main({ "no_such_dir" }, { root = ROOT, proc = proc, fs = fs })
  end)

  check.same(1, code)
  check.truthy(err:find("候选文件数为 0", 1, true) ~= nil, err)
  check.equal("COMMITTED", fs.files[ROOT .. "/.metrics/dry.edn"])
end)

-- 退 0 且没有零文件提示,但这次没写出 dry.edn:不能拿旧文件充数。
it("fails when dryer exits 0 without writing a new metrics file", function()
  local fs = _ready_fs({ [ROOT .. "/.metrics/dry.edn"] = "STALE" })
  local proc = _fake_proc(function(argv)
    if argv[#argv - 1] == "-c" then return PROBE_OK end
    return { ok = true, code = 0, output = "DUPLICATE score=1.00\n" }
  end)
  local code, _, err = _capture(function()
    return cli.main({ "src" }, { root = ROOT, proc = proc, fs = fs })
  end)

  check.same(1, code)
  check.truthy(err:find("未写出", 1, true) ~= nil, err)
  check.equal("STALE", fs.files[ROOT .. "/.metrics/dry.edn"])
end)

it("fails on a nonzero dryer exit and restores the committed metrics file", function()
  local fs = _ready_fs({ [ROOT .. "/.metrics/dry.edn"] = "COMMITTED" })
  local proc = _fake_proc(function(argv)
    if argv[#argv - 1] == "-c" then return PROBE_OK end
    fs.files[ROOT .. "/.metrics/dry.edn"] = "PARTIAL"
    return { ok = false, code = 1, output = "Unknown option: --bogus\n" }
  end)
  local code, _, err = _capture(function()
    return cli.main({ "--bogus" }, { root = ROOT, proc = proc, fs = fs })
  end)

  check.same(1, code)
  check.truthy(err:find("退出码 1", 1, true) ~= nil, err)
  check.equal("COMMITTED", fs.files[ROOT .. "/.metrics/dry.edn"])
end)

-- P2(#148):恢复失败时不能把备份也删掉,必须点名失败并保留唯一可用的基线。
it("keeps the backup and reports when restoring the metrics file fails", function()
  local fs = _ready_fs({ [ROOT .. "/.metrics/dry.edn"] = "COMMITTED" })
  local copies = {}
  local real_copy = fs.copy_file
  fs.copy_file = function(from, to)
    copies[#copies + 1] = { from = from, to = to }
    if to == ROOT .. "/.metrics/dry.edn" then return false end
    return real_copy(from, to)
  end
  local proc = _fake_proc(function(argv)
    if argv[#argv - 1] == "-c" then return PROBE_OK end
    fs.files[ROOT .. "/.metrics/dry.edn"] = "PARTIAL"
    return { ok = false, code = 1, output = "boom\n" }
  end)
  local code, _, err = _capture(function()
    return cli.main({ "src" }, { root = ROOT, proc = proc, fs = fs })
  end)

  check.same(1, code)
  check.truthy(err:find("恢复", 1, true) ~= nil, err)
  local backup = copies[#copies].from
  check.truthy(backup ~= ROOT .. "/.metrics/dry.edn", "restore should start from the backup")
  check.truthy(fs.files[backup] ~= nil, "backup must be kept when restore fails")
  check.is_nil(fs.files[ROOT .. "/.metrics/dry.edn"], "partial output must not survive")
end)

it("judges the metrics file under --root, not the repo root", function()
  local fs = _ready_fs({ [ROOT .. "/.metrics/dry.edn"] = "COMMITTED" })
  local proc = _fake_proc(function(argv)
    if argv[#argv - 1] == "-c" then return PROBE_OK end
    fs.files["D:/tmp/x/.metrics/dry.edn"] = "ISOLATED"
    return { ok = true, code = 0, output = "" }
  end)
  local code = _capture(function()
    return cli.main({ "--root", "D:/tmp/x" }, { root = ROOT, proc = proc, fs = fs })
  end)

  check.same(0, code)
  check.equal("COMMITTED", fs.files[ROOT .. "/.metrics/dry.edn"])
end)

end)

describe("real process", function()

local REAL_ROOT = env_lib.current_dir():gsub("\\", "/")
local ready = fs_lib.path_exists(dryer.checkout_dir(REAL_ROOT) .. "/pyproject.toml")
  and fs_lib.path_exists(dryer.python_path(REAL_ROOT))

local function _run(tail)
  local command = { require("foundation.lua54").lua54_bin(), "tools/cli.lua", "dry" }
  for _, value in ipairs(tail) do command[#command + 1] = value end
  return proc_lib.run_command(command)
end

-- 夹具扫描写到隔离 root,绝不改入库的 .metrics/dry.edn。
local function _with_isolated_root(fn)
  local root = env_lib.make_temp_path("dry_cli_spec", ""):gsub("\\", "/")
  fs_lib.remove_path(root)
  check.is_true(fs_lib.ensure_dir(root), "夹具目录建不起来: " .. root)
  local ok, err = xpcall(function() fn(root) end, debug.traceback)
  fs_lib.remove_path(root)
  if not ok then error(err) end
end

-- 环境缺失时唯一允许的结局是「不可用」(退 3、点名 checkout/venv),不是通过。
if not ready then
  it("without a dryer checkout the real command reports unavailable", function()
    local result = _run({ "src" })

    check.same(3, result.code, result.output)
    check.truthy(result.output:find("status=unavailable tool=dryer", 1, true) ~= nil, result.output)
  end)
  return
end

it("scans the duplicate fixture, finds the pair and writes a fresh metrics file", function()
  _with_isolated_root(function(root)
    local fixture = REAL_ROOT .. "/tools/packages/dry/test/fixtures/duplicate_pair"
    -- dryer 跳过路径里名为 test 的目录;夹具在 test/ 下,所以按文件显式点名(显式文件不受此限)。
    local result = _run({ "--root", root, fixture .. "/ledger_a.lua", fixture .. "/ledger_b.lua" })

    check.same(0, result.code, result.output)
    check.truthy(result.output:find("DUPLICATE score=", 1, true) ~= nil, result.output)
    check.truthy(result.output:find("ledger_a.lua", 1, true) ~= nil, result.output)
    check.truthy(result.output:find("ledger_b.lua", 1, true) ~= nil, result.output)
    local metrics = fs_lib.read_raw(root .. "/.metrics/dry.edn")
    check.truthy(metrics ~= nil and metrics:find(":candidates", 1, true) ~= nil, tostring(metrics))
  end)
end)

-- 防空扫描假绿:真实扫描 src/ 必须有候选文件并写出结果。
it("scans a non-empty candidate set under src", function()
  _with_isolated_root(function(root)
    local result = _run({ "--root", root, "-s", REAL_ROOT .. "/src" })

    check.same(0, result.code, result.output)
    check.is_nil(result.output:find("status=unavailable", 1, true), result.output)
    check.truthy(fs_lib.path_exists(root .. "/.metrics/dry.edn"), "src 扫描必须写出 dry.edn")
  end)
end)

it("a target without lua files fails instead of reporting no duplicates", function()
  _with_isolated_root(function(root)
    local result = _run({ "--root", root, "-s", root })

    check.same(1, result.code, result.output)
    check.truthy(result.output:find("候选文件数为 0", 1, true) ~= nil, result.output)
    check.is_false(fs_lib.path_exists(root .. "/.metrics/dry.edn"))
  end)
end)

end)

end)
