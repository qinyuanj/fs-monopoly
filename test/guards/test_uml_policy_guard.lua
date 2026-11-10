require("test.bootstrap").install_package_paths()

local luassert = assert
local guard = require("test.guards.lib.uml_policy_guard")

-- 仓根 policy.edn 入库(ADR 0082 第 2、3 条)::proposals / :omit 由 agent 按插件规则手改,
-- 其余键是 arch_policy.project_uml_policy 的镜像。用 M.check 喂合成文本:真实仓库
-- 已合规时测不出拦截是否生效。
local PROJECTED = table.concat({
  '{:title "Monopoly"',
  " :lang :lua",
  ' :src "src"',
  ' :prefix "src"',
  " :hierarchical true",
  " :levels [[:foundation] [:config :state] [:rules] [:computer :player] [:turn] [:ui] [:host] [:app]]",
  " :foreign []}",
  "",
}, "\n")

local function _policy(overrides)
  local values = {
    title = '"Monopoly"',
    lang = ":lua",
    src = '"src"',
    prefix = '"src"',
    hierarchical = "true",
    levels = "[[:foundation] [:config :state] [:rules] [:computer :player] [:turn] [:ui] [:host] [:app]]",
    foreign = "[]",
    out = '"tmp/uml/fs-monopoly.edn"',
    proposals = '[{:id :p-1 :layers [] :name "2026-11-05 16:40:19" :omit []}]',
    omit = "[]",
  }
  for key, value in pairs(overrides or {}) do
    values[key] = value
  end
  local lines = {}
  for _, key in ipairs({ "title", "lang", "src", "prefix", "hierarchical", "levels",
    "foreign", "out", "proposals", "omit" }) do
    if values[key] ~= false then
      lines[#lines + 1] = ":" .. key .. " " .. values[key]
    end
  end
  return "{" .. table.concat(lines, "\n ") .. "}\n"
end

describe("TestUmlPolicyGuard", function()
  it("test_policy_matching_the_projection_passes", function()
    luassert.is.same({}, guard.check(_policy(), PROJECTED))
  end)

  it("test_changed_levels_are_flagged_with_the_levels_edn_hint", function()
    local violations = guard.check(_policy({
      levels = "[[:foundation] [:config :state] [:rules] [:computer :player] [:turn] [:host] [:ui] [:app]]",
    }), PROJECTED)
    luassert.is.equal(2, #violations)
    luassert.truthy(violations[1]:find("uml_policy_guard: :levels differs from", 1, true), violations[1])
    luassert.truthy(violations[2]:find("tools/packages/arch_policy/levels.edn", 1, true), violations[2])
    luassert.truthy(violations[2]:find("policy.edn", 1, true), violations[2])
  end)

  it("test_any_proposals_or_omit_edit_passes", function()
    luassert.is.same({}, guard.check(_policy({
      proposals = '[{:id :ccp :name "rules ] } split" :layers [:rules :turn] :omit [cli]} {:id :x}]',
      omit = "[src.ui src.host]",
    }), PROJECTED))
    luassert.is.same({}, guard.check(_policy({ proposals = false, omit = false }), PROJECTED))
  end)

  it("test_layout_comments_and_key_order_do_not_matter", function()
    local text = table.concat({
      "; 插件写回的格式可能不同",
      "{:omit [], :foreign [] :levels [[:foundation], [:config :state] [:rules]",
      "  [:computer :player] [:turn] [:ui] [:host] [:app]] ; inline",
      ' :hierarchical true :prefix "src" :src "src" :lang :lua :title "Monopoly"',
      ' :out "tmp/uml/other.edn"}',
    }, "\r\n")
    luassert.is.same({}, guard.check(text, PROJECTED))
  end)

  it("test_missing_projection_key_is_flagged", function()
    local violations = guard.check(_policy({ foreign = false }), PROJECTED)
    luassert.is.same({ "uml_policy_guard: missing key :foreign (expected [])" },
      { violations[1] })
    luassert.is.equal(2, #violations)
  end)

  it("test_unexpected_extra_key_is_flagged", function()
    local violations = guard.check(_policy({ title = '"Monopoly" :theme :dark' }), PROJECTED)
    luassert.is.equal(2, #violations)
    luassert.truthy(violations[1]:find("unexpected key :theme", 1, true), violations[1])
  end)

  it("test_out_must_stay_under_ignored_tmp_uml", function()
    for _, out in ipairs({ false, '"docs/fs-monopoly.edn"', ":tmp/uml/x" }) do
      local violations = guard.check(_policy({ out = out }), PROJECTED)
      luassert.is.equal(2, #violations, tostring(out))
      luassert.truthy(violations[1]:find(":out must be a string under tmp/uml/", 1, true), violations[1])
    end
  end)

  it("test_malformed_policy_is_flagged_with_line", function()
    for _, text in ipairs({
      "",
      "[:levels []]",
      '{:title "Monopoly"\n :levels [[:app]',
      "{:title}",
      '{:title "a" :title "b"}',
      "{:levels []} trailing",
    }) do
      local violations = guard.check(text, PROJECTED)
      luassert.is.equal(2, #violations, text)
      luassert.truthy(violations[1]:find("uml_policy_guard: invalid policy.edn (line ", 1, true), violations[1])
    end
  end)

  it("test_real_repo_policy_matches_the_projection", function()
    local result = guard.run()
    luassert.is_true(result.ok, result.error)
  end)
end)
