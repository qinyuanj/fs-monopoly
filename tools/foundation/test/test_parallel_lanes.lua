---@diagnostic disable: undefined-global
require("test.bootstrap").install_package_paths()
local check = require("luassert")
local env = require("foundation.env")
local fs = require("foundation.fs")
local proc = require("foundation.proc")
local shell = require("foundation.shell")
local parallel = require("foundation.parallel_lanes")
local lua54 = require("foundation.lua54")
local native_lua = lua54.lua54_bin()

describe("native parallel lanes", function()

local function fixture(body)
  local root = env.make_temp_path("parallel_中文 space", "")
  assert(fs.ensure_dir(root))
  local ok, err = xpcall(function() body(root) end, debug.traceback)
  assert(fs.remove_path(root))
  assert(ok, err)
end

local function script(root, name, text)
  local file = root .. "/" .. name .. ".lua"
  assert(fs.write_file(file, text))
  return file
end

it("distinguishes success failure missing command and empty output", function()
  fixture(function(root)
    local writer = script(root, "writer", 'local d=os.time()+2; while os.time()<d do end; print("中文 success")')
    -- 字符串形态与数组形态都要覆盖:串行路径两处都经同一 shell 拼装。
    local success = native_lua .. " " .. shell.shell_quote(writer)
    local failure = script(root, "bad", 'print("out"); io.stderr:write("err\\n"); os.exit(4)')
    local silent = script(root, "empty", "os.exit(0)")
    local ok, results = parallel.run({
      { label = "ok", cmd = success },
      { label = "bad", cmd = shell.build_command({ native_lua, failure }) },
      { label = "missing", cmd = shell.build_command({ root .. "/missing_91" }) },
      { label = "empty", cmd = shell.build_command({ native_lua, silent }) },
    }, { stream = false, timeout = 20 })
    check.is_false(ok)
    check.same(4, #results)
    check.same("ok", results[1].label)
    check.is_true(results[1].ok)
    check.same(0, results[1].exit_code)
    check.is_not.equal(nil, results[1].owner_pid)
    check.is_not.equal(nil, results[1].child_pid)
    check.matches("中文 success", results[1].output, 1, true)
    check.same("exit", results[2].reason)
    check.same(4, results[2].exit_code)
    check.matches("err", results[2].output, 1, true)
    check.same("launch_failed", results[3].reason)
    check.same(127, results[3].exit_code)
    check.is_not.equal("", results[3].output)
    check.same("output_incomplete", results[4].reason)
    check.same(0, results[4].exit_code)
    check.is_not.equal(nil, results[4].message)
  end)
end)

it("exports opts.env to lane command trees", function()
  fixture(function(root)
    local reader = script(root, "env reader",
      'io.write(tostring(os.getenv("MONOPOLY_TEST_ENV_124") or "missing"))')
    local ok, results = parallel.run({
      { label = "env", cmd = shell.build_command({ native_lua, reader }) },
    }, { stream = false, timeout = 20, env = { MONOPOLY_TEST_ENV_124 = "value with space 100%" } })
    check.is_true(ok)
    check.same("value with space 100%", results[1].output)
  end)
end)

it("parallel and serial preserve order results and Chinese arguments", function()
  fixture(function(root)
    local file = script(root, "echo args", 'for i=1,#arg do print(arg[i]) end; os.exit(tonumber(arg[1]))')
    local first = { native_lua, file, "0", "", "中文 space", 'quote"and&pipe|', "%PATH%", "bang!caret^", "tail\\" }
    local second = { native_lua, file, "5", "参数 空格" }
    local lanes = {
      { label = "first", cmd = first },
      { label = "second", cmd = second },
    }
    local ok, results = parallel.run(lanes, { stream = false, timeout = 20 })
    check.is_false(ok)
    for index, lane in ipairs(lanes) do
      local serial = proc.run_command(lane.cmd)
      check.same(lane.label, results[index].label)
      check.same(serial.ok, results[index].ok)
      check.same(serial.code, results[index].exit_code)
      check.same(serial.output, results[index].output)
    end
  end)
end)

-- argv 表与串行路径逐字节一致:两处都由 shell.build_command 拼装,子进程看到的
-- arg[0](arg[-1])与串行相同。这条口径是 #107 的回归面,平台无关。
it("table command lanes preserve interpreter identity arg minus one", function()
  fixture(function(root)
    local file = script(root, "interp", 'print("ARGV_MINUS1=" .. tostring(arg[-1]))')
    local ok, results = parallel.run({ { label = "interp", cmd = { native_lua, file } } },
      { stream = false, timeout = 20 })
    check.is_true(ok)
    local serial = proc.run_command({ native_lua, file })
    check.same(serial.output, results[1].output)
    check.is_nil(results[1].output:find("ARGV_MINUS1=nil", 1, true),
      "interpreter identity lost: " .. results[1].output)
  end)
end)

-- 裸命令名分支:argv 首项是裸名时,lane 内 arg[-1] 也须与串行路径逐字节一致。
it("bare command name lanes resolve interpreter identity like serial", function()
  fixture(function(root)
    local file = script(root, "bare", 'print("ARGV_MINUS1=" .. tostring(arg[-1]))')
    local ok, results = parallel.run({
      { label = "a", cmd = { "lua5.4", file } }, { label = "b", cmd = { "lua5.4", file } },
    }, { stream = false, timeout = 20 })
    check.is_true(ok)
    local serial = proc.run_command({ "lua5.4", file })
    check.same(serial.output, results[1].output)
    check.same(serial.output, results[2].output)
  end)
end)

it("long Lua argv and lanes overlap", function()
  fixture(function(root)
    local file = script(root, "wait", [[
local started=os.time()
local deadline=started+3
while os.time()<deadline do end
print('INTERVAL '..started..' '..os.time())
print(#arg)
print(arg[1])
]])
    local args = { native_lua, file }
    for _ = 1, 1000 do args[#args + 1] = "中文 argument space" end
    local ok, results = parallel.run({
      { label = "a", cmd = args }, { label = "b", cmd = args },
    }, { stream = false, timeout = 20 })
    check.is_true(ok)
    local a_start, a_end = results[1].output:match("INTERVAL (%d+) (%d+)")
    local b_start, b_end = results[2].output:match("INTERVAL (%d+) (%d+)")
    check.is_true(math.max(tonumber(a_start), tonumber(b_start)) < math.min(tonumber(a_end), tonumber(b_end)), "actual worker intervals must overlap")
    check.matches("1000", results[1].output, 1, true)
    check.matches("中文 argument space", results[2].output, 1, true)
  end)
end)

it("timeout stops delayed writes and preserves unowned files", function()
  fixture(function(root)
    local marker = root .. "/late.txt"
    local file = script(root, "slow", [[
print("START")
io.stdout:flush()
local deadline=os.time()+8
while os.time()<deadline do end
local f=assert(io.open(arg[1],"wb")); f:write("LATE"); f:close()
]])
    assert(fs.write_file(root .. "/owned/sentinel.txt", "keep"))
    local ok, results = parallel.run({ { label = "slow", cmd = { native_lua, file, marker } } },
      { stream = false, timeout = 2, lane_dir = root .. "/owned" })
    check.is_false(ok)
    check.same("timeout", results[1].reason)
    check.matches("START", results[1].output, 1, true)
    check.is_nil(results[1].artifact_dir, "termination and cleanup must succeed")
    proc.run_command({ native_lua, "-e", "local d=os.time()+9; while os.time()<d do end; print('WAIT')" })
    check.is_false(fs.path_exists(marker), "timed-out child must not perform its delayed write")
    check.same("keep", fs.read_raw(root .. "/owned/sentinel.txt"))
    check.same(1, #assert(proc.collect_files(root .. "/owned")))
  end)
end)

-- lane 脚本与收容只依赖 sh / setsid / sleep,不引入编译器或宿主专用运行时
-- (Windows 时代的 PowerShell + Job Object 已随 ADR 0073 退场)。
it("lane owner needs no external compiler", function()
  fixture(function(root)
    local file = script(root, "builtin", 'print("BUILTIN_ONLY")')
    local driver = script(root, "driver",
      'require("test.bootstrap").install_package_paths(); '
        .. 'local ok,r=require("foundation.parallel_lanes").run({{label="builtin",cmd={'
        .. string.format('%q', native_lua) .. "," .. string.format('%q', file)
        .. '}}},{stream=false,timeout=20}); print(r[1].output); os.exit(ok and 0 or 1)')
    local result = proc.run_command({ native_lua, driver })
    check.is_true(result.ok, result.output)
    check.matches("BUILTIN_ONLY", result.output, 1, true)
  end)
end)

it("timeout stops detached writer after command parent exits", function()
  fixture(function(root)
    local marker = root .. "/detached_late.txt"
    local file = script(root, "detached", 'print("DETACHED_START"); io.stdout:flush(); local d=os.time()+6; while os.time()<d do end; local f=assert(io.open(arg[1],"wb")); f:write("LATE"); f:close()')
    -- 命令自身再派一个后台写手:收容必须按进程组覆盖,而不只是直接子进程。
    local command = shell.shell_quote(native_lua) .. " " .. shell.shell_quote(file) .. " "
      .. shell.shell_quote(marker) .. " & wait"
    local ok, results = parallel.run({{label="detached", cmd=command}}, {stream=false, timeout=2})
    check.is_false(ok)
    check.same("timeout", results[1].reason)
    check.matches("DETACHED_START", results[1].output, 1, true)
    check.is_nil(results[1].artifact_dir)
    proc.run_command({native_lua, "-e", "local d=os.time()+7; while os.time()<d do end; print('WAIT')"})
    check.is_false(fs.path_exists(marker), "detached owned writer must stop before timeout result returns")
  end)
end)
end)
