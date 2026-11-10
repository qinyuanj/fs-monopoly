require("test.bootstrap").install_package_paths()

local luassert = assert
local guard = require("test.guards.lib.docs_whitelist_guard")

-- 这个 guard 之前只跑在「已经合规的真实仓库」上,从没见过一个违规输入:把 .md 判断改成
-- ".XX"(等于什么都不查)、把退场目录检测改成 `if false`(等于防复发失效),guards 车道
-- 照样全绿。下面每一条都喂合成的违规输入,断言它**真的会红**——门禁的价值全在能变红。

local function reader(files)
  return function(path)
    return files[path]
  end
end

-- 合成的退场目录清单:让本 spec 语料无关——项目配置为空(如模板骨架)时防复发分支照样被验红。
local synthetic_retired_dirs = {
  "docs/inventory",
  "docs/reviews",
  "docs/superpowers",
  "docs/prototypes",
}

local function check(files, extra_paths)
  local paths = {}
  for path in pairs(files) do
    paths[#paths + 1] = path
  end
  table.sort(paths)
  for _, path in ipairs(extra_paths or {}) do
    paths[#paths + 1] = path
  end
  return guard.check(paths, reader(files), synthetic_retired_dirs)
end

local function joined(violations)
  return table.concat(violations, "\n")
end

local document = "# ok\n"

describe("TestDocsWhitelistGuard", function()
  it("test_passes_an_allowed_doc_without_front_matter", function()
    local violations = check({ ["docs/architecture.md"] = document })
    luassert.is.equal(0, #violations)
  end)

  -- 推演覆盖文件已退场(ADR 0082)::proposals/:omit 直接写在仓根 policy.edn,
  -- docs/ 下不再放行任何非 Markdown 资产,复活它即报红。
  it("test_flags_the_retired_uml_proposals_override", function()
    local violations = check({ ["docs/architecture.proposals.edn"] = "{:proposals []\n :omit []}\n" })
    luassert.is.equal(1, #violations)
    luassert.truthy(joined(violations):find("未在项目文档白名单", 1, true))
  end)

  it("test_flags_a_doc_outside_the_explicit_allowlist", function()
    local violations = check({ ["docs/notes.md"] = document })
    luassert.is.equal(1, #violations)
    luassert.truthy(joined(violations):find("未在项目文档白名单", 1, true))
  end)

  it("test_flags_non_markdown_assets_under_docs", function()
    local violations = check({ ["docs/diagram.png"] = "binary" })
    luassert.is.equal(1, #violations)
    luassert.truthy(joined(violations):find("未在项目文档白名单", 1, true))
  end)

  it("test_accepts_existing_repo_links_and_ignores_external_or_anchor_links", function()
    local violations = check({
      ["docs/architecture.md"] = table.concat({
        "[decision](decisions.md)",
        "[root](../CODING_STANDARDS.md)",
        "[section](#放置原则)",
        "[external](https://example.com/spec)",
      }, "\n"),
      ["docs/decisions.md"] = document,
      ["CODING_STANDARDS.md"] = document,
    })
    luassert.is.equal(0, #violations)
  end)

  it("test_flags_a_broken_relative_markdown_link", function()
    local violations = check({
      ["docs/architecture.md"] = "# Architecture\n\n[missing](./missing.md)\n",
    })
    luassert.is.equal(1, #violations)
    luassert.truthy(joined(violations):find("失效链接", 1, true))
    luassert.truthy(joined(violations):find("docs/missing.md", 1, true))
  end)

  it("test_flags_an_unreadable_md_file_instead_of_silently_skipping_it", function()
    -- reader 返回 nil = 读不到。若不报,坏文件会被当成合规无声放行。
    local violations = guard.check({ "docs/architecture.md" }, function() return nil end, synthetic_retired_dirs)
    luassert.is.equal(1, #violations)
    luassert.truthy(joined(violations):find("读不到", 1, true))
  end)

  -- 退场 effort 目录重新出现即违规。
  for _, retired in ipairs({ "inventory", "reviews", "superpowers", "prototypes" }) do
    it("test_flags docs/" .. retired .. "/ reappearing", function()
      local path = "docs/" .. retired .. "/report.md"
      local violations = check({ [path] = document })
      luassert.is.equal(1, #violations)
      luassert.truthy(joined(violations):find("禁用的 effort 目录", 1, true))
      luassert.truthy(joined(violations):find(path, 1, true))
    end)
  end

  it("test_reports_every_violation_not_just_the_first", function()
    local violations = check({
      ["docs/a.md"] = document,
      ["docs/b.md"] = document,
      ["docs/inventory/c.md"] = document,
    })
    luassert.is.equal(3, #violations)
  end)
end)
