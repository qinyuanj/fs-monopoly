require("test.bootstrap").install_package_paths()

local arch_policy = require("packages.arch_policy")
local policy_scan = require("packages.arch_policy.scan")

-- 层边界门禁(#92 / #214):公开加载链编译 policy.json 与 levels.edn 后执行,
-- 是 slim 里唯一的层边界门禁(旧外部分析器与其投影已于 #94 退场)。
local M = {}

local POLICY_PATH = arch_policy.DEFAULT_POLICY_PATH

local function _describe(violation)
  if violation.kind == "forbidden_dependency" then
    return "arch_policy_guard: forbidden_dependency [" .. tostring(violation.rule) .. "] "
      .. tostring(violation.from) .. " -> " .. tostring(violation.to)
  end
  if violation.kind == "layer_violation" then
    return "arch_policy_guard: layer_violation " .. tostring(violation.from)
      .. " (" .. tostring(violation.from_layer) .. ") -> " .. tostring(violation.to)
      .. " (" .. tostring(violation.to_layer) .. ")"
  end
  if violation.kind == "unclassified_module" then
    return "arch_policy_guard: unclassified_module " .. tostring(violation.module_id)
  end
  if violation.kind == "invalid_policy" then
    return "arch_policy_guard: invalid_policy " .. tostring(violation.component)
      .. ": " .. tostring(violation.message)
  end
  if violation.kind == "projection_cycle" then
    return "arch_policy_guard: projection_cycle " .. tostring(violation.cycle)
  end
  return "arch_policy_guard: " .. tostring(violation.kind)
end

function M.describe(violation)
  return _describe(violation)
end

-- 门禁判定接缝:吃一份已扫好的图,喂合成图即可验证合法/违规两侧。
function M.check_graph(policy, graph)
  local result = arch_policy.check(policy, graph)
  if result.ok then
    return { ok = true, message = "arch_policy_guard ok" }
  end
  local lines = { "arch_policy_guard failed" }
  for _, violation in ipairs(result.violations) do
    lines[#lines + 1] = _describe(violation)
  end
  return { ok = false, error = table.concat(lines, "\n") }
end

function M.run()
  local policy, load_err = arch_policy.load(POLICY_PATH)
  if policy == nil then
    return { ok = false, error = "arch_policy_guard error: " .. tostring(load_err) }
  end
  local graph, scan_err = policy_scan.graph(".", policy)
  if graph == nil then
    return { ok = false, error = "arch_policy_guard error: " .. tostring(scan_err) }
  end
  return M.check_graph(policy, graph)
end

return M
