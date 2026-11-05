--- Real busted execution; project events bracket the complete hook chain.
local M = {}
local initialize

local function run(files, helper, output, arguments, configure, settings)
  local busted = require("busted.core")()
  require("packages.test_runner.registration_trace").install(busted)
  local real_it
  local register = busted.register
  busted.register = function(descriptor, executor, attributes)
    if descriptor == "it" and type(executor) == "function" then real_it = executor end
    return register(descriptor, executor, attributes)
  end
  local api = require("busted")
  -- busted removes __call after initialization; retain its genuine initializer
  -- while preserving the verified module object and creating a fresh core.
  initialize = initialize or assert(getmetatable(api).__call, "busted initializer unavailable")
  initialize(api, busted)
  busted.register = register
  -- Preserve ordinary require identity across files. Specs own singleton patches.
  busted.register("file", "file", {})
  local counts = { files = #files, cases = 0, passed = 0, failed = 0, errors = 0 }
  local pending, current
  local file_cases = {}
  local function element(test)
    local names = { test.name }
    local parent = busted.context.parent(test)
    while parent and parent.descriptor ~= "file" do
      if parent.name then table.insert(names, 1, parent.name) end
      parent = busted.context.parent(parent)
    end
    return { name = test.name, full_name = table.concat(names, " "), trace = test.trace }
  end
  local function finish()
    if not pending then return end
    counts.cases = counts.cases + 1
    local bucket = pending.status == "success" and "passed" or pending.status == "failure" and "failed" or "errors"
    counts[bucket] = counts[bucket] + 1
    busted.publish({ "project", "case", "end" }, pending.element, nil, pending.status, pending.message)
    pending, current = nil, nil
  end
  busted.subscribe({ "error" }, function(test, _, message)
    if current then current.message = message; current.error = true
    else counts.errors = counts.errors + 1 end
    io.write("not ok - busted hook/load error: " .. tostring(test.name) .. "\n# " .. tostring(message):gsub("\n", "\n# ") .. "\n")
    return nil, true
  end)
  busted.subscribe({ "failure" }, function(test, _, message)
    if current then current.message = message end
    if test.descriptor ~= "it" then
      if current then current.error = true else counts.errors = counts.errors + 1 end
    end
    return nil, true
  end)
  busted.subscribe({ "test", "end" }, function(test, _, status)
    pending = { element = element(test), status = status, message = current and current.message }
    return nil, true
  end)
  local options = { arguments = arguments, busted = busted, counts = counts,
    capture_logs = settings and settings.capture_logs }
  if output == "TAP" then require("packages.test_runner.tap_handler").tap_handler_factory(options)
  else assert(loadfile(output))()(options) end
  if helper then assert(loadfile(helper))(options) end
  if configure then configure(busted, counts) end
  -- Wrap the genuine it executor at busted's public register seam. Its normal
  -- nested hook traversal is unchanged; project events bracket the whole call.
  busted.register("it", function(test)
    current = {}
    local project_element = element(test)
    project_element.trace = project_element.trace or {}
    local file = busted.getFile(test)
    if file then
      project_element.trace.source = "@" .. file.name
      file_cases[file.name] = (file_cases[file.name] or 0) + 1
    end
    busted.publish({ "project", "case", "start" }, project_element, nil)
    local status = busted.safe("it", function() real_it(test) end, test)
    if not pending then
      pending = { element = project_element, status = "error", message = "test hook failed before body" }
    end
    if not status:success() or current.error then pending.status = "error"; pending.message = current.message end
    finish()
  end)
  require("busted.modules.test_file_loader")(busted, { "lua" })(files, {}, { excludes = {}, recursive = false })
  require("busted.execute")(busted)(1, {})
  finish()
  for _, file in ipairs(files) do
    if not file_cases[file] then
      counts.errors = counts.errors + 1
      io.write("not ok - empty spec file: " .. file .. "\n")
    end
  end
  busted.publish({ "project", "suite", "end" })
  return counts
end
function M.run(files, helper, output, arguments, configure, settings)
  local original_print, original_write = _G.print, io.write
  local ok, result = pcall(run, files, helper, output, arguments, configure, settings)
  _G.print = original_print
  rawset(io, "write", original_write)
  if not ok then error(result, 0) end
  return result
end
return M
