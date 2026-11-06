---@diagnostic disable: undefined-global
require("test.bootstrap").install_package_paths()

-- luacheck: ignore 143 (genuine busted injects luassert)
local luassert = assert
local guard = require("test.guards.lib.test_lint.guard")
local fs_lib = require("foundation.fs")

-- 每条 fixture 都是合成 spec 源码,过真实 luacheck parser 验证 guard:
-- 对「断言只躲在条件分支里」真的会红,对合规写法放行——门禁的价值全在能变红。

local function _check(files)
  local paths = {}
  for path in pairs(files) do
    paths[#paths + 1] = path
  end
  return guard.check(paths, function(path)
    return files[path]
  end)
end

-- cb44141 之前 runner_spawn_carries_tool_discovery_env 的空转写法(原型 fixture)。
local _VACUOUS_IF = [=[
local check = require("luassert")
describe("spec lane", function()
  it("runner_spawn_carries_tool_discovery_env", function()
    local captured_options
    run({ run_command = function(command, options)
      captured_options = options
      return { ok = true }
    end })
    check.equal(0, 0)
    if captured_options ~= nil then
      check.truthy(captured_options.env.LUA54_BIN)
    end
  end)
end)
]=]

-- cb44141 修复后的写法:if/else 两个分支都断言。
local _BOTH_BRANCHES = [=[
local check = require("luassert")
describe("spec lane", function()
  it("runner_spawn_carries_tool_discovery_env", function()
    local captured_options = run()
    local expected = discover()
    if expected == nil then
      check.is_nil(captured_options)
    else
      check.truthy(captured_options.env.LUA54_BIN)
    end
  end)
end)
]=]

describe("TestLintGuard", function()
  it("test_flags_pre_cb44141_vacuous_if_as_red", function()
    local violations = _check({ ["test/behavior/x/test_env.lua"] = _VACUOUS_IF })
    luassert.is.equal(1, #violations)
    local line = violations[1]
    luassert.truthy(line:find("vacuous%-branch"))
    luassert.truthy(line:find("test/behavior/x/test_env.lua", 1, true))
    luassert.truthy(line:find("runner_spawn_carries_tool_discovery_env", 1, true))
  end)

  it("test_reports_the_line_of_the_offending_if", function()
    local violations = _check({ ["test/behavior/x/test_env.lua"] = _VACUOUS_IF })
    luassert.truthy(violations[1]:find(":10 ", 1, true) ~= nil
      or violations[1]:find(":10[ %]]") ~= nil)
  end)

  it("test_accepts_if_else_when_both_branches_assert", function()
    luassert.is.equal(0, #_check({ ["test/behavior/x/test_env.lua"] = _BOTH_BRANCHES }))
  end)

  it("test_flags_if_else_with_assertion_free_else_branch", function()
    local violations = _check({
      ["test/behavior/x/test_branch.lua"] = [=[
local check = require("luassert")
it("one_sided", function()
  local ok = run()
  if ok then
    check.is_true(ok)
  else
    recover()
  end
end)
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("one_sided", 1, true))
  end)

  it("test_accepts_helper_call_as_branch_assertion", function()
    -- helper 展开让 then 分支被认定为有断言;不展开的话这条会被误报成红。
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_helper.lua"] = [=[
local check = require("luassert")
local function assert_ok(result)
  check.equal(0, result.code)
end
it("helper_counts_in_branch", function()
  local result = run()
  if result.code ~= nil then
    assert_ok(result)
  else
    check.is_nil(result.code)
  end
end)
]=],
    }))
  end)

  it("test_flags_conditional_assertion_even_via_helper", function()
    local violations = _check({
      ["test/behavior/x/test_helper.lua"] = [=[
local check = require("luassert")
local function assert_ok(result)
  check.equal(0, result.code)
end
it("helper_still_conditional", function()
  local result = run()
  if result ~= nil then
    assert_ok(result)
  end
end)
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("helper_still_conditional", 1, true))
  end)

  it("test_does_not_expand_helper_that_itself_only_calls_another_helper", function()
    -- 多层 helper 不展开(工单 out of scope):outer_helper 体里没有直接断言,
    -- 调用它不算断言,这条 if 子树无断言可判,放行而非误报。
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_indirect.lua"] = [=[
local check = require("luassert")
local function inner_assert(result)
  check.equal(0, result.code)
end
local function outer_helper(result)
  inner_assert(result)
end
it("indirect_helper_is_not_expanded", function()
  local result = run()
  check.equal(0, result.code)
  if result.extra ~= nil then
    outer_helper(result)
  end
end)
]=],
    }))
  end)

  it("test_accepts_exemption_with_reason_on_previous_line", function()
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_allow.lua"] = [=[
local check = require("luassert")
it("allowed", function()
  local captured = run()
  -- lint-allow: vacuous-branch 兼容探测两种形态都合法(#122)
  if captured ~= nil then
    check.truthy(captured.env)
  end
end)
]=],
    }))
  end)

  it("test_accepts_exemption_on_the_same_line", function()
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_allow.lua"] = [=[
local check = require("luassert")
it("allowed_inline", function()
  local captured = run()
  if captured ~= nil then -- lint-allow: vacuous-branch 兼容探测(#122)
    check.truthy(captured.env)
  end
end)
]=],
    }))
  end)

  it("test_flags_exemption_without_reason_as_red", function()
    local violations = _check({
      ["test/behavior/x/test_allow.lua"] = [=[
local check = require("luassert")
it("not_allowed", function()
  local captured = run()
  -- lint-allow: vacuous-branch
  if captured ~= nil then
    check.truthy(captured.env)
  end
end)
]=],
    })
    luassert.is.equal(2, #violations)
    luassert.truthy(violations[1]:find("lint%-allow"))
    luassert.truthy(violations[1]:find("缺豁免理由", 1, true))
  end)

  it("test_flags_old_style_test_table_with_vacuous_branch", function()
    local violations = _check({
      ["test/behavior/legacy/test_old.lua"] = [=[
local luassert = assert(require("test.support.luassert_loader").load())
TestOld = {}
function TestOld.test_vacuous()
  local result = run()
  if result.ok then
    luassert.is_true(result.ok)
  end
end
function TestOld.test_covered()
  luassert.is_true(true)
end
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("TestOld.test_vacuous", 1, true))
  end)

  it("test_flags_old_style_table_constructor_form", function()
    local violations = _check({
      ["test/behavior/legacy/test_old.lua"] = [=[
local check = require("luassert")
local TestLegacy = {
  test_vacuous = function()
    local result = run()
    if result.ok then
      check.is_true(result.ok)
    end
  end,
  test_covered = function()
    check.is_true(true)
  end,
}
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("TestLegacy.test_vacuous", 1, true))
  end)

  it("test_ignores_bodies_with_no_assertions_at_all", function()
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_smoke.lua"] = [=[
it("smoke", function()
  local result = run()
  if result.ok then
    touch(result)
  end
end)
]=],
    }))
  end)

  it("test_accepts_loop_only_assertions_as_covered_leniently", function()
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_loop.lua"] = [=[
local check = require("luassert")
it("loop", function()
  local items = collect()
  for i = 1, #items do
    check.truthy(items[i].ok)
  end
end)
]=],
    }))
  end)

  it("test_resolves_it_target_passed_as_local_function_reference", function()
    local violations = _check({
      ["tools/packages/x/test/test_ref.lua"] = [=[
local check = require("luassert")
local function vacuous_case()
  local captured = run()
  if captured ~= nil then
    check.truthy(captured.env)
  end
end
describe("suite", function()
  it("referenced_case", vacuous_case)
end)
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("suite referenced_case", 1, true))
  end)

  it("test_skips_unresolvable_it_target_without_crashing", function()
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_dynamic.lua"] = [=[
it("dynamic", pick_case())
it("bare")
]=],
    }))
  end)

  it("test_flags_unreadable_spec_instead_of_silently_skipping_it", function()
    local violations = guard.check({ "test/behavior/x/test_gone.lua" }, function()
      return nil
    end)
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("读不到", 1, true))
  end)

  it("test_flags_unparsable_spec_instead_of_silently_skipping_it", function()
    local violations = _check({ ["test/behavior/x/test_broken.lua"] = "local =\n" })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("解析失败", 1, true))
  end)

  it("test_ignores_non_spec_paths", function()
    local vacuous = _VACUOUS_IF
    luassert.is.equal(0, #_check({
      ["src/rules/test_helper.lua"] = vacuous,
      ["test/support/cases.lua"] = vacuous,
      ["tools/packages/dry/test/fixtures/ledger_a.lua"] = vacuous,
      ["tools/packages/dry/runner.lua"] = vacuous,
    }))
  end)

  it("test_scans_tools_test_specs", function()
    local violations = _check({ ["tools/packages/dry/test/test_dry.lua"] = _VACUOUS_IF })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("tools/packages/dry/test/test_dry.lua", 1, true))
  end)

  it("test_violation_report_carries_guard_rule_path_line_and_test_name", function()
    local line = table.concat(_check({ ["test/behavior/x/test_env.lua"] = _VACUOUS_IF }), "\n")
    luassert.truthy(line:find("test_lint_guard: vacuous%-branch: test/behavior/x/test_env%.lua:%d+ %["))
  end)
end)

-- cb44141 之前 tools/foundation/test/test_bootstrap.lua 的两条 where_luarocks
-- 计数器写法(原型 fixture):stub 里自增,测试体断言内部调用次数。
local _PRE_CB44141_BOOTSTRAP = [=[
local check = require("luassert")
it("luarocks command reuses exported MONOPOLY_LUAROCKS_EXE without probing", function()
  local override = "D:/native/LuaRocks/bin/luarocks.exe"
  local where_luarocks = 0
  local captured_command
  _with_stubs({
    { target = proc_lib, key = "run_command", value = function(command)
      if command[1] == "where.exe" and command[2] == "luarocks.exe" then
        where_luarocks = where_luarocks + 1
      end
      captured_command = command
      return { ok = true, output = "" }
    end },
  }, function()
    bootstrap.ensure_luacheck_tree("/repo")
  end)
  check.equal(0, where_luarocks)
  check.equal(override, captured_command[1])
end)

it("missing MONOPOLY_LUAROCKS_EXE override falls back to probing", function()
  local where_luarocks = 0
  local captured_command
  _with_stubs({
    { target = proc_lib, key = "run_command", value = function(command)
      if command[1] == "where.exe" and command[2] == "luarocks.exe" then
        where_luarocks = where_luarocks + 1
        return { ok = false, output = "" }
      end
      captured_command = command
      return { ok = true, output = "" }
    end },
  }, function()
    bootstrap.ensure_luacheck_tree("/repo")
  end)
  check.equal(1, where_luarocks)
  check.truthy(captured_command[1]:match("luarocks%.exe$") ~= nil)
end)
]=]

-- cb44141 修复后的写法:断言解析出的路径(可见结果),不再数 where.exe 调用。
local _POST_CB44141_BOOTSTRAP = [=[
local check = require("luassert")
it("missing MONOPOLY_LUAROCKS_EXE override falls back to probing", function()
  local captured_command
  _with_stubs({
    { target = proc_lib, key = "run_command", value = function(command)
      if command[1] == "where.exe" and command[2] == "luarocks.exe" then
        return { ok = false, output = "" }
      end
      captured_command = command
      return { ok = true, output = "" }
    end },
  }, function()
    bootstrap.ensure_luacheck_tree("/repo")
  end)
  check.truthy(captured_command[1]:match("luarocks%.exe$") ~= nil)
end)
]=]

local function _call_count_hits(violations)
  local hits = {}
  for _, line in ipairs(violations) do
    if line:find("call%-count") then
      hits[#hits + 1] = line
    end
  end
  return hits
end

describe("TestLintGuard call-count", function()
  it("test_flags_pre_cb44141_bootstrap_counters_as_red", function()
    local violations = _check({ ["tools/foundation/test/test_bootstrap.lua"] = _PRE_CB44141_BOOTSTRAP })
    luassert.is.equal(2, #violations)
    local joined = table.concat(violations, "\n")
    luassert.truthy(joined:find(
      "test_lint_guard: call-count: tools/foundation/test/test_bootstrap.lua:17 "
        .. "[luarocks command reuses exported MONOPOLY_LUAROCKS_EXE without probing]", 1, true))
    luassert.truthy(joined:find(
      "test_lint_guard: call-count: tools/foundation/test/test_bootstrap.lua:36 "
        .. "[missing MONOPOLY_LUAROCKS_EXE override falls back to probing]", 1, true))
    luassert.truthy(joined:find("where_luarocks", 1, true))
  end)

  it("test_accepts_post_cb44141_bootstrap_rewrite", function()
    luassert.is.equal(0, #_check({ ["tools/foundation/test/test_bootstrap.lua"] = _POST_CB44141_BOOTSTRAP }))
  end)

  it("test_flags_assert_and_luassert_spellings_in_either_argument_order", function()
    local violations = _check({
      ["test/behavior/x/test_calls.lua"] = [=[
local luassert = require("luassert")
it("spellings", function()
  local calls = 0
  local stub = function() calls = 1 + calls end
  run(stub)
  assert.equal(1, calls)
  luassert.are.equal(calls, 1)
  assert.is_true(calls == 1)
end)
]=],
    })
    local hits = _call_count_hits(violations)
    luassert.is.equal(3, #hits)
    luassert.truthy(hits[1]:find(":6 ", 1, true))
    luassert.truthy(hits[2]:find(":7 ", 1, true))
    luassert.truthy(hits[3]:find(":8 ", 1, true))
  end)

  it("test_flags_the_real_pre_cb44141_test_bootstrap_and_accepts_the_current_one", function()
    -- 工单验收:对 cb44141 之前的 test_bootstrap.lua 原文判红,对当前仓库判绿。
    -- 原文存成 .txt fixture,避免被 lint 自己当 spec 扫描。
    local fixture = "test/guards/fixtures/call_count_pre_cb44141_bootstrap.lua.txt"
    local historical = fs_lib.read_file(fixture)
    luassert.truthy(historical, "missing historical fixture: " .. fixture)
    local path = "tools/foundation/test/test_bootstrap.lua"
    local violations = guard.check({ path }, function() return historical end)
    luassert.is.equal(7, #violations)
    local joined = table.concat(violations, "\n")
    for _, expected in ipairs({
      "call-count: " .. path .. ":316 [bootstrap luarocks command reuses exported MONOPOLY_LUAROCKS_EXE without probing]",
      "call-count: " .. path .. ":350 [bootstrap missing MONOPOLY_LUAROCKS_EXE override falls back to probing]",
    }) do
      luassert.truthy(joined:find(expected, 1, true), "missing historical hit: " .. expected .. "\n" .. joined)
    end
    luassert.truthy(joined:find("where_luarocks", 1, true))
    luassert.is.equal(0, #guard.check({ path }, fs_lib.read_file))
  end)

  it("test_flags_counter_asserted_inside_the_run_callback", function()
    -- _with_stubs(stubs, run) 的 run 回调也是嵌套函数;断言写在里面同样钉调用次数。
    local violations = _check({
      ["tools/foundation/test/test_inside.lua"] = [=[
local check = require("luassert")
it("inside_run", function()
  local calls = 0
  _with_stubs({
    { target = proc_lib, key = "run_command", value = function()
      calls = calls + 1
      return { ok = true }
    end },
  }, function()
    bootstrap.ensure_busted_tree("/repo")
    check.equal(1, calls)
  end)
end)
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("test_inside.lua:11 [inside_run]", 1, true))
  end)

  it("test_flags_old_style_test_table_counter", function()
    local violations = _check({
      ["test/behavior/legacy/test_old.lua"] = [=[
local luassert = assert(require("test.support.luassert_loader").load())
TestOld = {}
function TestOld.test_pins_calls()
  local n = 0
  host.on_tick = function() n = n + 1 end
  luassert.is.equal(2, n)
end
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("[TestOld.test_pins_calls]", 1, true))
  end)

  it("test_accepts_counting_observable_results_in_the_test_body_itself", function()
    -- 测试体自己的循环里数可见产物不是钉内部调用次数,放行。
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_tally.lua"] = [=[
local check = require("luassert")
it("tally", function()
  local result = run()
  local owned = 0
  for _, cell in ipairs(result.cells) do
    if cell.owner == "p1" then
      owned = owned + 1
    end
  end
  check.equal(3, owned)
end)
]=],
    }))
  end)

  it("test_accepts_counter_used_only_to_script_stub_responses", function()
    -- 计数只用来让 stub 第 N 次返回不同结果、从未被断言:不算钉调用次数。
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_retry.lua"] = [=[
local check = require("luassert")
it("retry", function()
  local attempts = 0
  local result = run(function()
    attempts = attempts + 1
    return attempts > 1
  end)
  check.is_true(result.ok)
end)
]=],
    }))
  end)

  it("test_accepts_exemption_with_reason_and_flags_one_without", function()
    local source = [=[
local check = require("luassert")
it("public_contract", function()
  local fired = 0
  bus.subscribe(function() fired = fired + 1 end)
  bus.publish()
  -- lint-allow: call-count 订阅回调恰好通知一次是 bus 的公共契约
  check.equal(1, fired)
end)
it("bare_allow", function()
  local fired = 0
  bus.subscribe(function() fired = fired + 1 end)
  bus.publish()
  -- lint-allow: call-count
  check.equal(1, fired)
end)
]=]
    local violations = _check({ ["test/behavior/x/test_bus.lua"] = source })
    luassert.is.equal(2, #violations)
    local joined = table.concat(violations, "\n")
    luassert.truthy(joined:find("lint-allow: call-count 缺豁免理由", 1, true))
    luassert.truthy(joined:find("call-count: test/behavior/x/test_bus.lua:14 [bare_allow]", 1, true))
    luassert.falsy(joined:find("[public_contract]", 1, true))
  end)

  it("test_vacuous_branch_exemption_does_not_cover_call_count", function()
    local violations = _check({
      ["test/behavior/x/test_cross.lua"] = [=[
local check = require("luassert")
it("cross", function()
  local calls = 0
  run(function() calls = calls + 1 end)
  -- lint-allow: vacuous-branch 规则名不匹配
  check.equal(1, calls)
end)
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find("call-count", 1, true))
  end)

  -- indexed-case-table:用例体放进函数数组、再由 it 按下标分派,用例体躲开
  -- 上面两条规则,漏注册的条目也不会被跑到。原型是迁移前的 test_roll_dice.lua。
  it("test_flags_indexed_case_table_as_red", function()
    local violations = _check({
      ["test/behavior/x/test_cases.lua"] = [=[
local check = require("luassert")
describe("cases", function()
  local _roll_tests = {
    function() check.equal(1, roll()) end,
    function() check.equal(2, roll()) end,
  }
  it("first", function() _roll_tests[1]() end)
end)
]=],
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(violations[1]:find(
      "indexed-case-table: test/behavior/x/test_cases.lua:3 ", 1, true))
    luassert.truthy(violations[1]:find("_roll_tests", 1, true))
  end)

  it("test_accepts_tables_mixing_functions_with_data", function()
    luassert.is.equal(0, #_check({
      ["test/behavior/x/test_cases.lua"] = [=[
local check = require("luassert")
local stub = { run = function() return 1 end }
local cases = { { name = "a", run = function() return 1 end } }
local hooks = { function() return 1 end, "tail" }
it("inline", function()
  check.equal(1, stub.run())
end)
]=],
    }))
  end)
end)
