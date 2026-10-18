local bootstrap = require("test.bootstrap")
local path_lib = require("foundation.path")
local proc_lib = require("foundation.proc")
local M = {}

local function repo_root()
  local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
  return path_lib.resolve_path(source:match("^(.*)/[^/]+$") or "test/support", "../..")
end

local function discover_behavior_specs()
  local root = repo_root():gsub("\\", "/"):gsub("/+$", "")
  local files = assert(proc_lib.collect_lua_files(path_lib.join_path(root, "test/behavior")))
  local specs = {}
  for _, file in ipairs(files) do
    file = file:gsub("\\", "/")
    if file:match("/test_[^/]+%.lua$") then
      if file:sub(1, #root + 1) == root .. "/" then file = file:sub(#root + 2) end
      specs[#specs + 1] = file
    end
  end
  table.sort(specs)
  return specs
end

M.behavior_suites = discover_behavior_specs()
M.contract_suites = { "test.support.tooling_suites.architecture.script_tools_contract" }

local function select_entries(entries, opts)
  local selected = {}
  for _, entry in ipairs(entries) do
    if not (opts and opts.only) or opts.only[entry] then selected[#selected + 1] = entry end
  end
  return selected
end

-- Discovery is data. Loading and hook execution belong to genuine busted.
function M.load_behavior_suites(opts)
  bootstrap.install_package_paths()
  return { busted_files = select_entries(M.behavior_suites, opts) }
end

function M.run_behavior_suites(suites, opts)
  opts = opts or {}
  local reporter = opts.reporter
  local capture_logs = opts.capture_logs ~= false and os.getenv("EGGY_TEST_VERBOSE") ~= "1"
  local files = assert(suites.busted_files, "real busted file collection required")
  assert(#files > 0, "no behavior spec files selected")
  local root = repo_root()
  local tool_bootstrap = dofile(path_lib.join_path(root, "tools/foundation/bootstrap.lua"))
  local env = tool_bootstrap.install(debug.getinfo(1, "S").source)
  -- busted / luassert 已由 test_runner 从受控 Lua 环境装载并校验;这里只复核
  -- 当前进程的依赖来源与身份,不再自举安装任何 rock。
  require("packages.test_runner.cache_loader").install(env.repo_root)
  local failures, summary, case_times, suite_times, slow_cases, suite_index = {}, {}, {}, {}, {}, {}
  local log_capture = require("test.support.log_capture")
  local slow_ms = tonumber(os.getenv("EGGY_TEST_SLOW_MS")) or 500
  local started, case_started = os.time(), nil
  local counts = require("packages.test_runner.busted_backend").run(files,
    path_lib.join_path(root, "test/helper.lua"), path_lib.join_path(root, "test/log_warns_handler.lua"), {},
    function(busted)
      busted.subscribe({ "project", "case", "start" }, function()
        case_started = os.time()
        return nil, true
      end)
      busted.subscribe({ "project", "case", "end" }, function(element, _, status, message)
        local name = element.full_name or element.name
        local file = tostring(element.trace and element.trace.source or "?"):gsub("^@", "")
        local elapsed = (os.time() - case_started) * 1000
        case_times[#case_times + 1] = { name = name, suite_name = file, elapsed_ms = elapsed, timer_source = "os.time" }
        if not suite_index[file] then
          suite_index[file] = { name = file, elapsed_ms = 0, case_count = 0, timer_source = "os.time" }
          suite_times[#suite_times + 1] = suite_index[file]
        end
        local suite = suite_index[file]
        suite.elapsed_ms, suite.case_count = suite.elapsed_ms + elapsed, suite.case_count + 1
        if elapsed >= slow_ms then slow_cases[#slow_cases + 1] = { name = name, ms = elapsed } end
        local captured = element.captured or { lines = {} }
        if status == "success" then
          log_capture.collect_summary(summary, captured)
          if reporter then reporter.case_pass(name, captured) end
        else
          failures[#failures + 1] = { name = name, err = message, captured = captured, status = status }
          if reporter then reporter.case_fail(name, message, captured) end
        end
        return nil, true
      end)
    end, { capture_logs = capture_logs })
  assert(counts.cases > 0, "busted quality collection empty result")
  while #failures < counts.failed + counts.errors do
    failures[#failures + 1] = { name = "busted hook/load/baseline", err = "infrastructure error", status = "error" }
  end
  if reporter then reporter.finish(summary, failures) end
  return { total = counts.cases, failures = failures, summary = summary, slow_cases = slow_cases,
    timing_data = { total_elapsed_ms = (os.time() - started) * 1000, suite_times = suite_times,
      case_times = case_times, timer_source = "os.time" },
    failed = #failures > 0, errors = counts.errors, counts = counts }
end

function M.load_contract_suites(opts)
  bootstrap.install_package_paths()
  local suites = {}
  for _, module_name in ipairs(select_entries(M.contract_suites, opts)) do
    local suite = require(module_name)
    local clone = { name = suite.name, layer = suite.layer or "contract", kind = suite.kind or "contract",
      module_name = module_name, tests = {} }
    for _, test in ipairs(suite.tests or suite) do
      local case = {}
      if type(test) == "function" then case.run = test
      else for key, value in pairs(test) do case[key] = value end end
      case.tags = case.tags or {}
      clone.tests[#clone.tests + 1] = case
    end
    suites[#suites + 1] = clone
  end
  return suites
end

return M
