---@diagnostic disable: undefined-global
require("test.bootstrap").install_package_paths()

-- luacheck: ignore 143 (genuine busted injects luassert)
local luassert = assert

local arch_policy = require("packages.arch_policy")

-- #92:层边界只有一份真源 —— `tools/packages/arch_policy/policy.json`。
-- uml-viewer 侧 policy 的 :levels 是它的投影,必须逐层一致,否则架构图与门禁
-- 可以静默漂移(旧外部架构工具的 config.json 投影已于 #94 随工具退场)。
local POLICY_PATH = arch_policy.DEFAULT_POLICY_PATH

local POLICY = assert(arch_policy.load(POLICY_PATH))

describe("TestArchPolicyProjection", function()

it("test_policy_carries_every_existing_rule", function()
  luassert.is.equal(10, #POLICY.component_rules)
  luassert.is.equal(6, #POLICY.forbidden_dependency_rules)
  luassert.is.equal(2, #POLICY.abstract_rules)
  luassert.is.same({ "src" }, POLICY.source_roots)
  local names = {}
  for _, rule in ipairs(POLICY.forbidden_dependency_rules) do
    names[rule.name] = true
  end
  for _, name in ipairs({
    "ui_no_player",
    "ui_no_computer",
    "ui_no_rules",
    "ui_schema_pure",
    "ui_state_no_coord",
    "ui_no_turn_loop",
  }) do
    luassert.is_true(names[name], "policy 丢失禁向规则: " .. name)
  end
end)

-- uml 侧 policy 的 :levels 是「越靠前越内层」的 rank 表:substrate 最内层,
-- 其余按层号从大到小。逐个组件核对 rank 的逆序关系,而不是只看字符串形状。
it("test_uml_levels_invert_the_declared_layers", function()
  local groups = arch_policy.uml_level_groups(POLICY)
  local rank_of = {}
  for rank, group in ipairs(groups) do
    for _, name in ipairs(group) do
      luassert.is_nil(rank_of[name], "组件在 :levels 里重复: " .. name)
      rank_of[name] = rank - 1
    end
  end

  local seen = 0
  for _, rule in ipairs(POLICY.component_rules) do
    local name = rule.component
    local rank = rank_of[name]
    luassert.is_not_nil(rank, "组件未出现在 uml :levels: " .. name)
    seen = seen + 1
    if rule.substrate == true then
      luassert.is.equal(0, rank, "substrate 必须是最内层 rank 0")
    else
      luassert.is.equal(8 - rule.layer, rank,
        "组件 " .. name .. " 的 uml rank 必须与其声明层号互逆")
    end
  end
  luassert.is.equal(#POLICY.component_rules, seen)
end)

it("test_uml_policy_text_uses_the_policy_source", function()
  local text = arch_policy.project_uml_policy(POLICY)
  luassert.is_not_nil(text:find(":prefix \"src\"", 1, true))
  luassert.is_not_nil(text:find(":src \"src\"", 1, true))
  luassert.is_not_nil(text:find(":levels [[:foundation] [:config :state] [:rules]"
    .. " [:computer :player] [:turn] [:ui] [:host] [:app]]", 1, true))
end)
end)
