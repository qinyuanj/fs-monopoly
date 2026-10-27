---@diagnostic disable: undefined-global, undefined-field
require("test.bootstrap").install_package_paths()
local luassert = assert

local arch_policy = require("packages.arch_policy")

-- 本仓自己的 arch 规则表断言(#596;#214 起由加载链合并层配置与其余规则)。
--
-- 为什么需要它:arch_policy_guard 只在「policy 里声明了某条规则」时才会报违例。
-- 规则本身被删掉、改名或缩小 from/to 时,门禁照样全绿——不是因为架构守住了,
-- 而是因为没人再检查。arch_policy 的单测用合成 policy 验证机制,这里补上
-- 「本仓确实声明了这些规则」这一侧。
local function _rule(name)
  local policy = assert(arch_policy.load(arch_policy.DEFAULT_POLICY_PATH))
  for _, rule in ipairs(policy.forbidden_dependency_rules or {}) do
    if rule.name == name then
      return rule
    end
  end
  return nil
end

describe("TestArchConfigRules", function()
  -- ui.state 拥有展示状态,ui.coord 消费它并驱动视图/宿主副作用;层序把两者都算
  -- ui(3),所以这条方向约束不在层门禁覆盖范围内,必须由显式规则承担
  -- (docs/architecture.md「ui 内部」一节)。
  it("test_ui_state_must_not_depend_on_ui_coord", function()
    local rule = _rule("ui_state_no_coord")
    luassert.truthy(rule ~= nil,
      "arch policy 必须声明 ui_state_no_coord 规则,否则 ui.state 反向依赖 ui.coord 无人拦截")
    luassert.is.same({ "^src%.ui%.state%..+" }, rule.from,
      "ui_state_no_coord 的 from 必须覆盖整个 src.ui.state 子树")
    luassert.is.same({ "^src%.ui%.coord%..+" }, rule.to,
      "ui_state_no_coord 的 to 必须覆盖整个 src.ui.coord 子树")
  end)

  -- 回合循环运行时以 turn → ui 方向调用 ui;层序允许 ui(3) 依赖 turn(4),所以
  -- ui 反过来 require 回合循环会形成隐性双向边而层门禁不拦(#206 C / #211)。
  -- 锁输入谓词已下沉到 src.state.input_lock,ui 应向内依赖它。
  it("test_ui_must_not_depend_on_turn_loop", function()
    local rule = _rule("ui_no_turn_loop")
    luassert.truthy(rule ~= nil,
      "arch policy 必须声明 ui_no_turn_loop 规则,否则 ui 重新 require 回合循环无人拦截")
    luassert.is.same({ "^src%.ui%..+" }, rule.from,
      "ui_no_turn_loop 的 from 必须覆盖整个 src.ui 子树")
    luassert.is.same({ "^src%.turn%.loop$", "^src%.turn%.loop%..+" }, rule.to,
      "ui_no_turn_loop 的 to 必须覆盖 src.turn.loop 及其子树")
  end)
end)
