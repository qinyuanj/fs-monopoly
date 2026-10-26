---@diagnostic disable: undefined-global
if arg then rawset(arg, 0, "tools/packages/uml_quality/test/test_uml_quality_proposals.lua") end
require("test.bootstrap").install_package_paths()

-- uml ir 的覆盖文件合并(#99 / ADR 0070):policy.edn 是 project_uml_policy 的生成物,
-- 唯一人手维护的 :proposals / :omit 存在 docs/architecture.proposals.edn,生成时合并。
local check = require("luassert")
local proposals = require("packages.uml_quality.proposals")

local PROJECTED = '{:title "UML"\n :lang :lua\n :levels [[:foundation] [:app]]\n :foreign []}\n'
local OUT = "tmp/uml/fs-monopoly.edn"

describe("uml ir proposals override", function()

it("treats a missing override file as no proposals and no omit", function()
  local text = assert(proposals.merge(PROJECTED, nil, OUT))
  check.truthy(text:find(':levels [[:foundation] [:app]]', 1, true))
  check.truthy(text:find(':out "tmp/uml/fs-monopoly.edn"', 1, true))
  check.truthy(text:find(":proposals []", 1, true))
  check.truthy(text:find(":omit []", 1, true))
end)

it("treats an empty or comment-only override file as no proposals and no omit", function()
  for _, override in ipairs({ "", "  \r\n", "; 推演写这里\n" }) do
    local text = assert(proposals.merge(PROJECTED, override, OUT))
    check.truthy(text:find(":proposals []", 1, true))
    check.truthy(text:find(":omit []", 1, true))
  end
end)

-- 每次重生都从投影起步;覆盖文件里的推演必须原样带进生成的 policy,不被冲掉。
it("carries proposals and omit from the override into the generated policy", function()
  local override = table.concat({
    "; 维护者推演",
    "{:proposals [{:id :ccp :name \"rules split\" :layers [:rules :turn] :omit [cli]}]",
    " :omit [ui.debug]}",
  }, "\n")
  local text = assert(proposals.merge(PROJECTED, override, OUT))
  check.truthy(text:find(':proposals [{:id :ccp :name "rules split" :layers [:rules :turn] :omit [cli]}]', 1, true))
  check.truthy(text:find(":omit [ui.debug]", 1, true))
  check.truthy(text:find(':levels [[:foundation] [:app]]', 1, true))
  check.truthy(text:match("}%s*$"))
end)

it("keeps delimiters inside strings and comments from ending a value early", function()
  local override = '{:proposals [{:id :p :name "a ] } b"} ; ] }\n] :omit []}'
  local text = assert(proposals.merge(PROJECTED, override, OUT))
  check.truthy(text:find('{:id :p :name "a ] } b"}', 1, true))
end)

-- 反例:覆盖文件不能变成第二份 policy,多余键一律报错。
it("rejects keys other than :proposals and :omit", function()
  local text, err = proposals.merge(PROJECTED, "{:proposals [] :levels [[:app]]}", OUT)
  check.is_nil(text)
  check.truthy(err:find(":levels", 1, true))
  check.truthy(err:find(":proposals", 1, true))
end)

it("rejects duplicate keys", function()
  local text, err = proposals.merge(PROJECTED, "{:omit [] :omit [a]}", OUT)
  check.is_nil(text)
  check.truthy(err:find("duplicate", 1, true))
end)

it("rejects malformed EDN with a readable error", function()
  for _, override in ipairs({
    "{:proposals [",
    "[:proposals []]",
    "{:proposals}",
    "{:proposals [] :omit \"x\"}",
    '{:proposals ["unterminated]}',
    "{:proposals []} {:omit []}",
    "{:proposals [)]}",
  }) do
    local text, err = proposals.merge(PROJECTED, override, OUT)
    check.is_nil(text, override)
    check.truthy(err ~= nil and err:find("architecture.proposals.edn", 1, true), override)
  end
end)

end)
