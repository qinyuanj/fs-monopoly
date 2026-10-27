-- packages/arch_policy —— 架构边界的公开加载与检查链(工单 #92 / #214)。
--
-- 层序与同层分组只由 levels.edn 声明;policy.json 保留模块匹配、substrate、
-- 禁向依赖与环豁免。load 将两份配置编译成内存策略,guard 与 UML 投影都消费它:
--   1. `test/guards/lib/arch_policy_guard.lua` 执行门禁(层方向/环/未分类/
--      禁向边),不依赖外部 rock 的分析器;
--   2. `project_uml_policy` 直接投影编译后的层组,不反向猜测数字层号。
--
-- 规则语义与 ADR 0001/0002、ADR 0039 D2 一致:L1 最高、数字越大层越低;
-- foundation 是 substrate(谁都能依赖它,它不依赖任何整型层)。环检测契约保留:
-- 每个视图的反馈边闭合路径逐条判定,白名单按 view 和路径参与者集合豁免。
local json_reader = require("foundation.json_reader")

local M = {}

M.DEFAULT_POLICY_PATH = "tools/packages/arch_policy/policy.json"
M.DEFAULT_LEVELS_PATH = "tools/packages/arch_policy/levels.edn"

local function _matches_any(module_id, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if tostring(module_id or ""):match(pattern) ~= nil then
      return true
    end
  end
  return false
end

-- module_id 命中的 component 规则;未命中即未分类模块。
function M.component_rule(policy, module_id)
  for _, rule in ipairs(policy.component_rules or {}) do
    if _matches_any(module_id, rule.match) then
      return rule
    end
  end
  return nil
end

-- 门禁口径的声明层:整型层号、substrate,或 nil(未分类)。
-- substrate 故意没有整型值,从而永不进入数值不等式。
function M.declared_layer(policy, module_id)
  local rule = M.component_rule(policy, module_id)
  if rule == nil then
    return nil
  end
  if rule.substrate == true then
    return "substrate"
  end
  return rule.layer
end

local function _is_layer_upward(from_layer, to_layer)
  if from_layer == nil or to_layer == nil then
    return false
  end
  if from_layer == "substrate" then
    return to_layer ~= "substrate"
  end
  if to_layer == "substrate" then
    return false
  end
  return from_layer > to_layer
end

-- 强连通分量:每个分量即一条环。返回按分量内最小模块名排序的分量表,
-- 分量内模块名升序,整体确定。
local function _cycles(module_ids, adjacency)
  local index_of = {}
  local low = {}
  local on_stack = {}
  local stack = {}
  local components = {}
  local counter = 0

  local function strongconnect(node)
    counter = counter + 1
    index_of[node] = counter
    low[node] = counter
    stack[#stack + 1] = node
    on_stack[node] = true
    for _, to in ipairs(adjacency[node] or {}) do
      if index_of[to] == nil then
        strongconnect(to)
        low[node] = math.min(low[node], low[to])
      elseif on_stack[to] then
        low[node] = math.min(low[node], index_of[to])
      end
    end
    if low[node] == index_of[node] then
      local component = {}
      repeat
        local member = stack[#stack]
        stack[#stack] = nil
        on_stack[member] = false
        component[#component + 1] = member
      until member == node
      if #component > 1 then
        table.sort(component)
        components[#components + 1] = component
      end
    end
  end

  for _, module_id in ipairs(module_ids) do
    if index_of[module_id] == nil then
      strongconnect(module_id)
    end
  end
  table.sort(components, function(a, b) return a[1] < b[1] end)
  return components
end

local function _same_members(component, waiver_nodes)
  if #component ~= #waiver_nodes then
    return false
  end
  local members = {}
  for _, member in ipairs(component) do
    members[member] = true
  end
  for _, node in ipairs(waiver_nodes) do
    if not members[node] then
      return false
    end
  end
  return true
end

local function _waiver_for(policy, component, view)
  for _, waiver in ipairs(policy.allowed_cycles or {}) do
    if waiver.view == view and _same_members(component, waiver.nodes or {}) then
      return waiver
    end
  end
  return nil
end

-- 图形态:{ modules = {"src.app", ...}, edges = {{from=, to=}, ...} }
-- 只判定两张表都在 modules 里的边;外部 require 不进图。
function M.check(policy, graph)
  for _, rule in ipairs(policy.component_rules or {}) do
    local layer = rule.layer
    if rule.substrate ~= true and (type(layer) ~= "number" or layer < 1 or layer % 1 ~= 0) then
      local violation = {
        kind = "invalid_policy",
        component = rule.component or rule.name,
        message = "ordinary component has no compiled positive integer layer",
      }
      return { ok = false, violations = { violation }, all_violations = { violation } }
    end
  end

  local modules = graph.modules or {}
  local known = {}
  for _, module_id in ipairs(modules) do
    known[module_id] = true
  end

  local violations = {}
  local sorted_modules = {}
  for _, module_id in ipairs(modules) do
    sorted_modules[#sorted_modules + 1] = module_id
  end
  table.sort(sorted_modules)

  for _, module_id in ipairs(sorted_modules) do
    if M.component_rule(policy, module_id) == nil then
      violations[#violations + 1] = { kind = "unclassified_module", module_id = module_id }
    end
  end

  local edges = {}
  for _, edge in ipairs(graph.edges or {}) do
    if known[edge.from] and known[edge.to] and edge.from ~= edge.to then
      edges[#edges + 1] = edge
    end
  end
  table.sort(edges, function(a, b)
    if a.from ~= b.from then return a.from < b.from end
    return a.to < b.to
  end)

  for _, edge in ipairs(edges) do
    for _, rule in ipairs(policy.forbidden_dependency_rules or {}) do
      if _matches_any(edge.from, rule.from) and _matches_any(edge.to, rule.to) then
        violations[#violations + 1] = {
          kind = "forbidden_dependency",
          rule = rule.name,
          description = rule.description,
          from = edge.from,
          to = edge.to,
        }
      end
    end
    local from_layer = M.declared_layer(policy, edge.from)
    local to_layer = M.declared_layer(policy, edge.to)
    if _is_layer_upward(from_layer, to_layer) then
      violations[#violations + 1] = {
        kind = "layer_violation",
        from = edge.from,
        to = edge.to,
        from_layer = from_layer,
        to_layer = to_layer,
      }
    end
  end

  -- 每个命名空间视图把后代折叠为直接子节点;模块图无环也可能投影成环。
  local namespaces, views = {}, { root = "" }
  for _, id in ipairs(sorted_modules) do
    local ns = id:gsub("^src%.", "")
    namespaces[id] = ns
    local prefix = ""
    local parts = {}
    for part in ns:gmatch("[^.]+") do parts[#parts + 1] = part end
    for index = 1, #parts - 1 do
      prefix = prefix == "" and parts[index] or prefix .. "." .. parts[index]
      views[prefix] = prefix
    end
  end
  local view_keys = {}
  for view in pairs(views) do view_keys[#view_keys + 1] = view end
  table.sort(view_keys)
  for _, view in ipairs(view_keys) do
    local prefix = views[view]
    local children, node_set, projected = {}, {}, {}
    for id, ns in pairs(namespaces) do
      local rest = prefix == "" and ns or
        (ns:sub(1, #prefix + 1) == prefix .. "." and ns:sub(#prefix + 2) or nil)
      if rest then
        local child = rest:match("^[^.]+")
        if child then
          local full = prefix == "" and child or prefix .. "." .. child
          children[id], node_set[full] = full, true
        end
      end
    end
    for _, edge in ipairs(edges) do
      local from, to = children[edge.from], children[edge.to]
      if from and to and from ~= to then
        projected[from] = projected[from] or {}
        projected[from][to] = true
      end
    end
    local nodes, links = {}, {}
    for node in pairs(node_set) do nodes[#nodes + 1] = node end
    table.sort(nodes)
    for from, targets in pairs(projected) do
      links[from] = {}
      for to in pairs(targets) do links[from][#links[from] + 1] = to end
      table.sort(links[from])
    end
    local paths = require("packages.arch_policy.cycles").paths(nodes, links, _cycles(nodes, links))
    for _, cycle in ipairs(paths) do
      local component = {}
      for index = 1, #cycle - 1 do component[#component + 1] = cycle[index] end
      local waiver = _waiver_for(policy, component, view)
      violations[#violations + 1] = {
        kind = "projection_cycle",
        view = view,
        cycle = table.concat(component, "->") .. "->" .. component[1],
        nodes = component,
        waived = waiver ~= nil,
        reason = waiver and waiver.reason or nil,
      }
    end
  end

  local failing = {}
  for _, violation in ipairs(violations) do
    if violation.waived ~= true then
      failing[#failing + 1] = violation
    end
  end

  return { ok = #failing == 0, violations = failing, all_violations = violations }
end

local function _edn_string(value)
  local escaped = tostring(value or ""):gsub("\\", "\\\\"):gsub("\"", "\\\"")
  return "\"" .. escaped .. "\""
end

-- 组序即 levels.edn 的内层优先顺序;加载器已验证完整性,投影不再按层号重排。
function M.uml_level_groups(policy)
  assert(type(policy.level_groups) == "table", "arch policy has no compiled level groups")
  return policy.level_groups
end

function M.project_uml_policy(policy)
  local groups = {}
  for _, group in ipairs(M.uml_level_groups(policy)) do
    groups[#groups + 1] = "[:" .. table.concat(group, " :") .. "]"
  end
  local foreign = {}
  for _, name in ipairs(policy.foreign or {}) do
    foreign[#foreign + 1] = ":" .. tostring(name)
  end
  return table.concat({
    "{:title " .. _edn_string(policy.title or "UML"),
    " :lang :lua",
    " :src " .. _edn_string((policy.source_roots or {})[1] or "src"),
    " :prefix " .. _edn_string(policy.module_prefix or ""),
    " :hierarchical true",
    " :levels [" .. table.concat(groups, " ") .. "]",
    " :foreign [" .. table.concat(foreign, " ") .. "]}",
    "",
  }, "\n")
end

local function _levels_error(path, line, message)
  return string.format("invalid arch levels %s (line %d): %s", tostring(path), line or 1, message)
end

local function _compile_levels(policy, groups, lines, levels_path)
  if type(policy) ~= "table" or type(policy.component_rules) ~= "table" then
    return nil, "invalid arch policy: component_rules must be an array"
  end
  local components = {}
  for _, rule in ipairs(policy.component_rules) do
    local name = type(rule) == "table" and rule.component or nil
    if type(name) ~= "string" or name == "" then
      return nil, "invalid arch policy: every component rule needs a component name"
    end
    if components[name] ~= nil then
      return nil, "invalid arch policy: duplicate component " .. name
    end
    if rule.layer ~= nil then
      return nil, "invalid arch policy: numeric layer moved to " .. tostring(M.DEFAULT_LEVELS_PATH)
    end
    components[name] = rule
  end

  local seen = {}
  for group_index, group in ipairs(groups) do
    local substrate_in_group = false
    for _, name in ipairs(group) do
      local rule = components[name]
      if rule == nil then
        return nil, _levels_error(levels_path, lines[name], "unknown component :" .. name)
      end
      seen[name] = true
      substrate_in_group = substrate_in_group or rule.substrate == true
      if rule.substrate == true and group_index ~= 1 then
        return nil, _levels_error(levels_path, lines[name], "substrate must be in the innermost group")
      end
    end
    for _, name in ipairs(group) do
      if substrate_in_group and components[name].substrate ~= true then
        return nil, _levels_error(levels_path, lines[name], "substrate cannot share a group with ordinary components")
      end
    end
  end
  for name in pairs(components) do
    if not seen[name] then
      return nil, _levels_error(levels_path, 1, "missing component :" .. name)
    end
  end

  for group_index, group in ipairs(groups) do
    for _, name in ipairs(group) do
      if components[name].substrate ~= true then
        components[name].layer = #groups - group_index + 1
      end
    end
  end
  policy.level_groups = groups
  return policy
end

function M.load(path, levels_path)
  local fs_lib = require("foundation.fs")
  local raw = fs_lib.read_file(path)
  if raw == nil then
    return nil, "cannot read arch policy: " .. tostring(path)
  end
  local ok, policy = pcall(json_reader.decode, raw)
  if not ok then
    return nil, "cannot decode arch policy " .. tostring(path) .. ": " .. tostring(policy)
  end

  if levels_path == nil then
    local parent = require("foundation.path").parent_dir(path)
    levels_path = (parent or ".") .. "/levels.edn"
  end
  local levels_raw = fs_lib.read_file(levels_path)
  if levels_raw == nil then
    return nil, _levels_error(levels_path, 1, "cannot read arch levels")
  end
  local groups, lines, read_err = require("packages.arch_policy.levels").read(levels_raw, levels_path)
  if groups == nil then return nil, read_err end
  return _compile_levels(policy, groups, lines, levels_path)
end

return M
