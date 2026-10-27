---@diagnostic disable: undefined-global
require("test.bootstrap").install_package_paths()

-- luacheck: ignore 143 (genuine busted injects luassert)
local luassert = assert

local arch_policy = require("packages.arch_policy")
local fs = require("foundation.fs")
local env_lib = require("foundation.env")

local VALID_LEVELS = [=[{:levels [[:foundation]
 [:config :state]
 [:rules]
 [:computer :player]
 [:turn]
 [:ui]
 [:host]
 [:app]]}]=]

local function _load_with_levels(text)
  local root = env_lib.make_temp_path("arch_policy_levels", "")
  fs.remove_path(root)
  local policy_path = root .. "/policy.json"
  local levels_path = root .. "/levels.edn"
  assert(fs.write_file(policy_path, assert(fs.read_raw(arch_policy.DEFAULT_POLICY_PATH))))
  if text ~= nil then assert(fs.write_file(levels_path, text)) end
  local policy, err = arch_policy.load(policy_path, levels_path)
  fs.remove_path(root)
  return policy, err
end

-- #214:层序与同层分组唯一真源是 levels.edn;policy.json 保留其余边界。
-- guard 与 UML 投影都经公开加载链消费编译结果,避免各自解释层配置。
local POLICY_PATH = arch_policy.DEFAULT_POLICY_PATH

local POLICY = assert(arch_policy.load(POLICY_PATH))

describe("TestArchPolicyProjection", function()

it("test_real_level_config_compiles_stable_groups_and_legacy_layers", function()
  luassert.is_not_nil(fs.read_raw(arch_policy.DEFAULT_LEVELS_PATH))
  luassert.is.same({
    { "foundation" },
    { "config", "state" },
    { "rules" },
    { "computer", "player" },
    { "turn" },
    { "ui" },
    { "host" },
    { "app" },
  }, POLICY.level_groups)
end)

it("test_policy_json_no_longer_declares_numeric_layers", function()
  local raw = assert(fs.read_raw(arch_policy.DEFAULT_POLICY_PATH))
  local decoded = assert(require("foundation.json_reader").decode(raw))
  for _, rule in ipairs(decoded.component_rules) do
    luassert.is_nil(rule.layer, "组件策略不得再保存数字层号: " .. rule.component)
  end
end)

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

it("test_level_reader_accepts_whitespace_commas_comments_and_crlf", function()
  local text = "; preface\r\n{, :levels, [ ; groups\r\n"
    .. "[:foundation], [:config, :state], [:rules], [:computer, :player],\r\n"
    .. "[:turn], [:ui], [:host], [:app]], } ; tail\r\n"
  local policy, err = _load_with_levels(text)
  luassert.is_not_nil(policy, err)
  luassert.is.same(POLICY.level_groups, policy.level_groups)
end)

it("test_malformed_level_configs_fail_with_source_and_line", function()
  for _, text in ipairs({
    "{}",
    "{:levels []}",
    "{:levels [[:app]] :levels [[:host]]}",
    "{:levels [[:app]] :other []}",
    "{:levels [[]]}",
    "{:levels [[app]]}",
    "{:levels [[\"app\"]]}",
    "{:levels [[:core/app]]}",
    "{:levels [[:app]]",
    "{:levels [[:app]]} garbage",
  }) do
    local policy, err = _load_with_levels(text)
    luassert.is_nil(policy, text)
    luassert.is_not_nil(err:find("levels.edn (line ", 1, true), text)
  end
end)

it("test_missing_level_config_fails_without_fallback", function()
  local policy, err = _load_with_levels(nil)
  luassert.is_nil(policy)
  luassert.is_not_nil(err:find("cannot read arch levels", 1, true))
  luassert.is_not_nil(err:find("levels.edn (line 1)", 1, true))
end)

it("test_inconsistent_level_configs_fail_closed", function()
  local missing = VALID_LEVELS:gsub("%s*%[:app%]", "")
  local duplicate = VALID_LEVELS:gsub("%[:app%]", "[:app :app]")
  local unknown = VALID_LEVELS:gsub("%[:app%]", "[:mystery]")
  local misplaced = VALID_LEVELS:gsub(":foundation", ":substrate_placeholder")
    :gsub(":app", ":foundation"):gsub(":substrate_placeholder", ":app")
  local mixed = VALID_LEVELS:gsub("%[:foundation%]", "[:foundation :app]")
    :gsub("%s*%[:app%]%]", "]")

  for _, case in ipairs({
    { text = missing, message = "missing component :app" },
    { text = duplicate, message = "duplicate component :app" },
    { text = unknown, message = "unknown component :mystery" },
    { text = misplaced, message = "substrate must be in the innermost group" },
    { text = mixed, message = "substrate cannot share a group with ordinary components" },
  }) do
    local policy, err = _load_with_levels(case.text)
    luassert.is_nil(policy, case.text)
    luassert.is_not_nil(err:find("levels.edn (line ", 1, true), case.text)
    luassert.is_not_nil(err:find(case.message, 1, true), case.text)
  end
end)
end)
