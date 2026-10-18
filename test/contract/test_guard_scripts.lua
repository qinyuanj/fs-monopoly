-- luacheck: ignore 143 (genuine busted injects luassert)
local luassert = assert

require("test.bootstrap").install_package_paths()

local dep_rules = require("test.guards.lib.dep_rules")
local forbidden_globals = require("test.guards.lib.forbidden_globals")
local fixed_type_guard = require("test.guards.lib.fixed_type_guard")
local path_lib = require("foundation.path")

local fixture_root = path_lib.normalize_path("test/fixtures/guards")

local function _fixture_path(relpath)
  return path_lib.join_path(fixture_root, relpath)
end

describe("TestGuardScripts", function()

it("test_dep_rules_catches_ui_runtime_bypass", function()
  local result = dep_rules.run({
    rules = {
      {
        roots = { _fixture_path("dep_rules/ui_runtime_bypass/src/turn.lua") },
        forbidden_patterns = { "state%.ui_[A-Za-z0-9_]+%s*=" },
        description = "turn flow must route UI writes through output/ui_sync ports",
      },
    },
    forbidden_files = {},
  })

  luassert.is_true(result.ok == false, "dep_rules should reject direct state.ui_* writes")
  luassert.is_not_nil(result.violation, "dep_rules should report a violation")
  luassert.is_not_nil(result.violation.path:find("src/turn.lua", 1, true), "dep_rules should point to fixture file")
end)

local function _tool_foundation_rules(fixture)
  local rules = {}
  for _, rule in ipairs(require("test.guards.config.dep_rules").rules) do
    if rule.roots[1] == "tools/foundation" then
      rules[#rules + 1] = {
        roots = { _fixture_path("dep_rules/tool_packages/" .. fixture) },
        forbidden_patterns = rule.forbidden_patterns,
        description = rule.description,
      }
    end
  end
  return rules
end

it("test_dep_rules_rejects_tool_packages_in_foundation", function()
  local result = dep_rules.run({ rules = _tool_foundation_rules("bad.lua") })
  luassert.is_false(result.ok, "foundation must reject tool package dependencies")
  luassert.is_not_nil(result.violation)
  luassert.matches("tool_packages/bad.lua", result.violation.path, 1, true)
end)

for _, fixture in ipairs({ "script_argv.lua", "script_command.lua", "script_dofile.lua", "script_loadfile.lua" }) do
  it("test_dep_rules_rejects_direct_tool_package_script_" .. fixture, function()
    local result = dep_rules.run({ rules = _tool_foundation_rules(fixture) })
    luassert.is_false(result.ok, "foundation must reject direct tool package scripts")
    luassert.is_not_nil(result.violation)
    luassert.matches("tool_packages/" .. fixture, result.violation.path, 1, true)
  end)
end

it("test_dep_rules_allows_foundation_dependencies", function()
  local result = dep_rules.run({ rules = _tool_foundation_rules("clean.lua") })
  luassert.is_true(result.ok, "foundation may depend on other foundation modules")
end)

it("test_forbidden_globals_catches_numeric_cast_in_src", function()
  local result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/numeric_cast/src/bad.lua") },
  })

  luassert.is_true(result.ok == false, "forbidden_globals should reject tonumber in src")
  luassert.is_true(result.violations ~= nil and #result.violations == 1,
    "forbidden_globals should report one violation")
  luassert.is.equal("tonumber", result.violations[1].name, "forbidden_globals should identify tonumber")
end)

it("test_forbidden_globals_catches_src_package_access", function()
  local result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/src_package/src/bad.lua") },
  })

  luassert.is_true(result.ok == false, "forbidden_globals should reject package access in src")
  luassert.is_true(result.violations ~= nil and #result.violations == 1,
    "forbidden_globals should report one package violation")
  luassert.is.equal("package.*", result.violations[1].name, "forbidden_globals should identify package access")
end)

it("test_forbidden_globals_allows_numeric_cast_outside_src", function()
  local tests_result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/numeric_cast/tests/bad.lua") },
  })
  local tools_result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/numeric_cast/tools/bad.lua") },
  })

  luassert.is_true(tests_result.ok == true, "forbidden_globals should allow numeric casts in tests")
  luassert.is_true(tools_result.ok == true, "forbidden_globals should allow numeric casts in tools")
end)

it("test_forbidden_globals_allows_package_access_outside_src", function()
  local tests_result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/package_allowed/tests/clean.lua") },
  })
  local tools_result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/package_allowed/tools/clean.lua") },
  })

  luassert.is_true(tests_result.ok == true, "forbidden_globals should allow package access in tests")
  luassert.is_true(tools_result.ok == true, "forbidden_globals should allow package access in tools")
end)

it("test_forbidden_globals_catches_host_globals_in_ui", function()
  local result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/host_globals/src/ui/direct_call.lua") },
  })

  luassert.is_true(result.ok == false, "forbidden_globals should reject direct host global usage in src/ui")
  luassert.is_not_nil(result.violations, "forbidden_globals should report violations")
  local names = {}
  for _, violation in ipairs(result.violations) do
    names[violation.name] = true
  end
  luassert.is_true(names.GameAPI, "should flag GameAPI")
  luassert.is_true(names.LuaAPI, "should flag LuaAPI")
  luassert.is_true(names.SceneUI, "should flag SceneUI")
  luassert.is_true(names.Enums, "should flag Enums")
  luassert.is_true(names.RegisterCustomEvent, "should flag RegisterCustomEvent")
  luassert.is_true(names.UnregisterCustomEvent, "should flag UnregisterCustomEvent")
end)

it("test_forbidden_globals_allows_host_globals_in_ui_manager", function()
  local result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/host_globals/src/ui/manager/allowed.lua") },
  })

  luassert.is_true(result.ok == true, "forbidden_globals should allow direct host global usage in src/ui/manager")
end)

it("test_forbidden_globals_allows_host_globals_in_host", function()
  local result = forbidden_globals.run({
    scan_roots = { _fixture_path("forbidden_globals/host_globals/src/host/allowed.lua") },
  })

  luassert.is_true(result.ok == true, "forbidden_globals should allow direct host global usage in src/host")
end)

it("test_guard_scripts_allow_clean_fixtures", function()
  local dep_result = dep_rules.run({
    rules = {
      {
        roots = { _fixture_path("clean/src/clean.lua") },
        forbidden_patterns = { "state%.ui_[A-Za-z0-9_]+%s*=" },
        description = "turn flow must route UI writes through output/ui_sync ports",
      },
    },
    forbidden_files = {},
  })
  local globals_result = forbidden_globals.run({
    scan_roots = { _fixture_path("clean/tools/clean.lua") },
  })

  luassert.is_true(dep_result.ok == true, "dep_rules should allow clean fixtures")
  luassert.is_true(globals_result.ok == true, "forbidden_globals should allow clean fixtures")
end)

it("test_fixed_type_catches_int_literals", function()
  local result = fixed_type_guard.run({
    scan_roots = { _fixture_path("fixed_type/int_literal/src") },
  })

  luassert.is_true(result.ok == false, "fixed_type_guard should reject integer literals in Fixed-typed params")
  luassert.is_true(result.violations ~= nil and #result.violations >= 3,
    "fixed_type_guard should report at least 3 violations")
end)

it("test_fixed_type_allows_float_literals", function()
  local result = fixed_type_guard.run({
    scan_roots = { _fixture_path("fixed_type/float_literal/src") },
  })

  luassert.is_true(result.ok == true, "fixed_type_guard should allow float literals for Fixed-typed params")
end)

it("test_fixed_type_allows_clean_src", function()
  local result = fixed_type_guard.run({
    scan_roots = { _fixture_path("clean/src") },
  })

  luassert.is_true(result.ok == true, "fixed_type_guard should allow clean source files")
end)

end)
