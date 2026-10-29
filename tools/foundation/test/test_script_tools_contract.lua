if arg then rawset(arg, 0, "tools/foundation/test/test_script_tools_contract.lua") end
local suite = require("test.support.tooling_suites.architecture.script_tools_contract")

-- 脚本工具契约的唯一挂载点:每行一个 owner,新增消费者只在这里加一行。
-- 套件里 owner 不在本表的用例会在 "every case has a registered owner" 判红,
-- 不会静默漏跑。
local OWNERS = {
  { owner = "foundation", label = "foundation" },
  { owner = "bootstrap", label = "bootstrap" },
  -- CLI 双语帮助及入口解释器预检的公开策略契约。
  { owner = "tooling_policy", label = "policy" },
  { owner = "encoding", label = "encoding" },
  { owner = "deploy", label = "deploy" },
}

local CASE_LISTS = { suite.tests, suite.tooling_tests }

for _, row in ipairs(OWNERS) do
  describe("script tools " .. row.label .. " contracts", function()
    for _, cases in ipairs(CASE_LISTS) do
      for _, case in ipairs(suite.cases_for_owner(cases, row.owner)) do
        it(case.name, case.run)
      end
    end
  end)
end

describe("script tools contract table", function()
  it("every case has a registered owner", function()
    local registered = {}
    for _, row in ipairs(OWNERS) do
      registered[row.owner] = true
    end
    local orphans = {}
    for _, cases in ipairs(CASE_LISTS) do
      for _, case in ipairs(cases) do
        if registered[case.owner] ~= true then
          orphans[#orphans + 1] = tostring(case.owner) .. ":" .. tostring(case.name)
        end
      end
    end
    assert.same({}, orphans)
  end)
end)
