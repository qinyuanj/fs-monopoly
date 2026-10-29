---@diagnostic disable: undefined-global
require("test.bootstrap").install_package_paths()

local luassert = assert

local function _build_violation_report(name, violations)
  local lines = {}
  for _, violation in ipairs(violations or {}) do
    lines[#lines + 1] =
      name
      .. ": "
      .. tostring(violation.path)
      .. ":"
      .. tostring(violation.line)
      .. " uses "
      .. tostring(violation.name)
      .. " (use "
      .. tostring(violation.replacement)
      .. " instead)"
    lines[#lines + 1] = "  " .. tostring(violation.text)
  end
  return table.concat(lines, "\n")
end

local function _build_report(name, result)
  local ok = result ~= nil and result.ok == true
  if ok then
    return ok, result.message or (name .. " ok")
  end

  if result and result.error then
    return ok, name .. " error: " .. tostring(result.error)
  end

  if result and result.violations then
    return ok, _build_violation_report(name, result.violations)
  end

  return ok, name .. " failed"
end

local guards = {
  {
    name = "arch_policy_guard",
    module = "test.guards.lib.arch_policy_guard",
  },
  {
    name = "fixed_type_guard",
    module = "test.guards.lib.fixed_type_guard",
  },
  {
    name = "host_role_type_guard",
    module = "test.guards.lib.host_role_type_guard",
  },
  {
    name = "forbidden_globals",
    module = "test.guards.lib.forbidden_globals",
  },
  {
    name = "gameplay_loop_no_ui",
    module = "test.guards.lib.gameplay_loop_no_ui",
  },
  {
    name = "repo_hygiene",
    module = "test.guards.lib.repo_hygiene",
  },
  {
    name = "root_whitelist_guard",
    module = "test.guards.lib.root_whitelist_guard",
  },
  {
    name = "eggy_json_guard",
    module = "test.guards.lib.eggy_json_guard",
  },
  {
    name = "docs_whitelist_guard",
    module = "test.guards.lib.docs_whitelist_guard",
  },
  {
    name = "debug_flags_guard",
    module = "test.guards.lib.debug_flags_guard",
  },
  {
    name = "same_name_pair_guard",
    module = "test.guards.lib.same_name_pair_guard",
  },
  {
    name = "cli_command_table_guard",
    module = "test.guards.lib.cli_command_table_guard",
  },
  {
    name = "cli_shape_guard",
    module = "test.guards.lib.cli_shape_guard",
  },
  {
    name = "test_lint_guard",
    module = "test.guards.lib.test_lint.guard",
  },
}

describe("TestGuardRunner", function()
  for _, guard in ipairs(guards) do
    local runner = require(guard.module)

    it("test_" .. guard.name .. "_passes", function()
      local ok, report = _build_report(guard.name, runner.run())
      luassert.is_true(ok, report)
    end)
  end
end)
