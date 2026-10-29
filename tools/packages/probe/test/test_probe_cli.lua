---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/probe/test/test_probe_cli.lua") end

require("test.bootstrap").install_package_paths()

-- probe 子命令:从 main 入口驱动,子进程执行器、互操作探测、文件读写与时钟全部注入;
-- 只观察退出码、stdout/stderr 与交给 editor-cli exec 的代码文本。
local check = require("luassert")
local probe_cli = require("packages.probe.cli")
local script = require("packages.probe.script")

local HOME = "/mnt/c/Users/tester"
local CLI_DIR = HOME .. "/.eggitor/cli"
local MARKER = "DEBUG-PROBE-1700000000-abcd1234"

local STATUS_PLAYING = table.concat({
  "Editor Status:",
  "  running                True",
  "  edit_mode              False",
  "  in_game_runtime        True",
  "",
}, "\n")

local STATUS_EDITING = table.concat({
  "Editor Status:",
  "  running                True",
  "  edit_mode              True",
  "  in_game_runtime        False",
  "",
}, "\n")

local GREP_HIT = table.concat({
  '> 41: [20:08:38.529] [info/client] "' .. MARKER .. '"\t"cash"\t1500',
  '  42: [20:08:38.530] [info/client] context line',
  '> 43: [20:08:38.531] [info/client] "' .. MARKER .. '"\t"done"',
  "matches=2 omitted=0 totalMatchesKnown=true",
  "",
}, "\n")

local GREP_MISS = "(no matches)\nmatches=0 omitted=0 totalMatchesKnown=true\n"

local function _sink()
  local chunks = {}
  return {
    write = function(_, ...)
      for _, chunk in ipairs({ ... }) do
        chunks[#chunks + 1] = tostring(chunk)
      end
    end,
    text = function()
      return table.concat(chunks)
    end,
  }
end

-- 假 editor-cli:按 argv[2] 分派;grep_outputs 依次吐出,用尽后重复最后一个。
-- 记录 exec 收到的代码文本(经注入的 write_file 落在内存里)。
local function _harness(overrides)
  overrides = overrides or {}
  local files = { ["probe.lua"] = overrides.source or "probe('cash', 1500)\n" }
  local state = { exec_code = nil, exec_called = false, clock = 0 }
  local grep_outputs = overrides.grep_outputs or { GREP_HIT }
  local grep_index = 0
  local stdout, stderr = _sink(), _sink()

  local env = {
    command_exists = function(name)
      return not (overrides.missing or {})[name]
    end,
    resolve_home = function()
      return overrides.home or HOME
    end,
    file_exists = function(path)
      if overrides.exe_missing and path == CLI_DIR .. "/editor-cli.exe" then
        return false
      end
      return true
    end,
    read_file = function(path)
      return files[path]
    end,
    write_file = function(path, text)
      files[path] = text
      return true
    end,
    remove_file = function(path)
      files[path] = nil
    end,
    now = function()
      return 1700000000
    end,
    random_hex = function()
      return "abcd1234"
    end,
    clock = function()
      return state.clock
    end,
    sleep = function(seconds)
      state.clock = state.clock + seconds
    end,
    run = function(argv, options)
      check.equal(CLI_DIR, options.cwd)
      check.equal("./editor-cli.exe", argv[1])
      local sub = argv[2]
      if sub == "status" then
        return overrides.status or { ok = true, code = 0, output = STATUS_PLAYING }
      elseif sub == "exec" then
        state.exec_called = true
        check.equal("--file", argv[3])
        state.exec_code = files[CLI_DIR .. "/" .. argv[4]]
        return overrides.exec or { ok = true, code = 0, output = "" }
      elseif sub == "log" then
        check.equal("grep", argv[3])
        check.equal(MARKER, argv[4])
        grep_index = math.min(grep_index + 1, #grep_outputs)
        return { ok = true, code = 0, output = grep_outputs[grep_index] }
      end
      error("unexpected editor-cli call: " .. tostring(sub))
    end,
    stdout = stdout,
    stderr = stderr,
  }
  return env, state, stdout, stderr, files
end

local function _run(args, overrides)
  local env, state, stdout, stderr, files = _harness(overrides)
  local code = probe_cli.main(args, env)
  return code, stdout.text(), stderr.text(), state, files
end

describe("probe script", function()
  it("wraps the script after an injected probe() that prints the marker", function()
    local code = script.wrap("probe('x')\n", MARKER)

    check.truthy(code:find("^EditorAPI%.game_execute%(%[==%[\n"), code)
    check.truthy(code:find("\n%]==%]%)\n$"), code)
    check.truthy(code:find("local function probe(...) print('DEBUG-PROBE-' .. '1700000000-abcd1234', ...) end\n"
      .. "probe('x')\n", 1, true), code)
    -- 标记在游戏内拼接,源码文本里不出现完整标记,回显不会自命中。
    check.is_nil(code:find(MARKER, 1, true))
  end)

  it("raises the long bracket level past any closing bracket in the script", function()
    local source = "local s = [==[ a ]==] .. [===[ b ]===]\nprobe(\"q'\", s)"
    local code = script.wrap(source, MARKER)

    check.truthy(code:find("^EditorAPI%.game_execute%(%[====%[\n"), code)
    check.truthy(code:find("\n%]====%]%)\n$"), code)
    check.truthy(code:find(source, 1, true), "script text should be embedded verbatim")
    -- 包装结果是合法 Lua,且内层字符串原样还原。
    local captured
    local chunk = assert(load(code, "=wrapped", "t", {
      EditorAPI = { game_execute = function(text) captured = text end },
    }))
    chunk()
    check.equal(script.prelude(MARKER) .. "\n" .. source .. "\n", captured)
  end)

  it("does not mistake a trailing ']=' in the script for the closing bracket", function()
    local source = "local t = {}\n-- ends with ]="
    local captured
    assert(load(script.wrap(source, MARKER), "=wrapped", "t", {
      EditorAPI = { game_execute = function(text) captured = text end },
    }))()
    check.equal(script.prelude(MARKER) .. "\n" .. source .. "\n", captured)
  end)
end)

describe("probe cli", function()
  it("prints only the hit lines without the line-number prefix", function()
    local code, out, err, state = _run({ "probe.lua" })

    check.equal(0, code, err)
    check.equal('[20:08:38.529] [info/client] "' .. MARKER .. '"\t"cash"\t1500\n'
      .. '[20:08:38.531] [info/client] "' .. MARKER .. '"\t"done"\n', out)
    check.truthy(state.exec_code:find("probe('cash', 1500)", 1, true), state.exec_code)
    check.truthy(state.exec_code:find("^EditorAPI%.game_execute%("), state.exec_code)
  end)

  it("removes the temporary exec file after submitting it", function()
    local code, _, err, _, files = _run({ "probe.lua" })

    check.equal(0, code, err)
    for path in pairs(files) do
      check.is_nil(path:find(".probe-", 1, true), "temporary script left behind: " .. path)
    end
  end)

  it("keeps polling until the marker shows up", function()
    local code, out, err = _run({ "probe.lua" }, { grep_outputs = { GREP_MISS, GREP_MISS, GREP_HIT } })

    check.equal(0, code, err)
    check.truthy(out:find('"cash"\t1500', 1, true), out)
  end)

  it("refuses to run outside a playtest and asks the user to start one", function()
    local code, out, err, state = _run({ "probe.lua" }, {
      status = { ok = true, code = 0, output = STATUS_EDITING },
    })

    check.equal(1, code)
    check.equal("", out)
    check.truthy(err:find("in_game_runtime", 1, true), err)
    check.truthy(err:find("开启试玩", 1, true), err)
    check.is_false(state.exec_called, "nothing may be executed outside a playtest")
  end)

  it("exits 1 when the marker never appears before the timeout", function()
    local code, out, err = _run({ "probe.lua", "--timeout", "2" }, { grep_outputs = { GREP_MISS } })

    check.equal(1, code)
    check.equal("", out)
    check.truthy(err:find("2 秒内", 1, true), err)
    check.truthy(err:find(MARKER, 1, true), err)
  end)

  it("exits 1 with the editor output when exec fails", function()
    local code, out, err = _run({ "probe.lua" }, {
      exec = { ok = false, code = 4, output = "EXEC_INPUT_ERROR boom\n" },
    })

    check.equal(1, code)
    check.equal("", out)
    check.truthy(err:find("EXEC_INPUT_ERROR boom", 1, true), err)
  end)

  it("reports missing interop as unavailable with exit 3", function()
    local code, out, err, state = _run({ "probe.lua" }, { missing = { ["wslpath"] = true } })

    check.equal(3, code)
    check.equal("", out)
    check.truthy(err:find("status=unavailable tool=editor-cli step=interop", 1, true), err)
    check.truthy(err:find("wslpath", 1, true), err)
    check.is_false(state.exec_called)
  end)

  it("reports an unresolvable USERPROFILE as unavailable with exit 3", function()
    local code, _, err = _run({ "probe.lua" }, { home = "" })

    check.equal(3, code)
    check.truthy(err:find("status=unavailable tool=editor-cli step=userprofile", 1, true), err)
  end)

  it("reports a missing editor-cli.exe as unavailable with exit 3", function()
    local code, _, err = _run({ "probe.lua" }, { exe_missing = true })

    check.equal(3, code)
    check.truthy(err:find("status=unavailable tool=editor-cli step=executable", 1, true), err)
  end)

  it("reports an unreachable editor as unavailable with exit 3", function()
    local code, _, err, state = _run({ "probe.lua" }, {
      status = { ok = false, code = 1, output = "CONNECTION_ERROR no editor\n" },
    })

    check.equal(3, code)
    check.truthy(err:find("status=unavailable tool=editor-cli step=status", 1, true), err)
    check.truthy(err:find("CONNECTION_ERROR", 1, true), err)
    check.is_false(state.exec_called)
  end)

  it("exits 1 when the lua file cannot be read", function()
    local code, _, err = _run({ "missing.lua" })

    check.equal(1, code)
    check.truthy(err:find("missing.lua", 1, true), err)
  end)

  it("prints usage for --help", function()
    local code, out = _run({ "--help" })

    check.equal(0, code)
    check.truthy(out:find("lua5.4 tools/cli.lua probe <lua文件>", 1, true), out)
    check.truthy(out:find("--timeout", 1, true), out)
  end)

  it("treats malformed arguments as usage errors", function()
    for _, args in ipairs({
      {},
      { "a.lua", "b.lua" },
      { "probe.lua", "--timeout" },
      { "probe.lua", "--timeout", "0" },
      { "probe.lua", "--timeout", "abc" },
      { "probe.lua", "--bogus" },
    }) do
      local code, _, err, state = _run(args)
      check.equal(2, code, table.concat(args, " "))
      check.truthy(err:find("用法", 1, true), err)
      check.is_false(state.exec_called)
    end
  end)
end)
