require("test.bootstrap").install_package_paths()

local luassert = assert
local guard = require("test.guards.lib.root_whitelist_guard")

-- #490 放行条目退役钉：dependency-checker.edn 与
-- implementation-order.md 是 squad analyst 的根级产物,随 squad 范式退场——白名单
-- 恢复报违规,重引入放行即破此钉。guard 只跑在「已经合规的真实仓库」上时测不出
-- 放行是否生效,所以一律用 M.check 喂合成输入。

describe("TestRootWhitelistGuard", function()
  it("test_dependency_checker_edn_retired", function()
    local violations = guard.check({ "dependency-checker.edn" })
    luassert.is.equal(1, #violations)
    luassert.is.equal("dependency-checker.edn", violations[1])
  end)

  it("test_implementation_order_md_retired", function()
    local violations = guard.check({ "implementation-order.md" })
    luassert.is.equal(1, #violations)
    luassert.is.equal("implementation-order.md", violations[1])
  end)

  it("test_root_readme_is_retired", function()
    local violations = guard.check({ "README.md" })
    luassert.is.same({ "README.md" }, violations)
  end)

  -- uml-viewer 只在项目根读 uml-quality.json(#93);安装拷贝、覆盖率 target/
  -- 走 .gitignore,不进白名单——放开它们即破此钉。
  it("test_uml_quality_config_whitelisted_but_not_its_local_outputs", function()
    luassert.is.same({}, guard.check({ "uml-quality.json" }))
    luassert.is.same({ ".uml-viewer", "target", "uml", "uml.ps1" },
      guard.check({ ".uml-viewer", "target", "uml", "uml.ps1" }))
  end)

  -- 维护者决定按上游 README 将 .metrics/(真实 uml crap|mutate 的度量)入库(#69):
  -- 入库后它是已跟踪的根级条目,必须在白名单里,否则 guard 会拦住提交。
  it("test_versioned_uml_metrics_dir_whitelisted", function()
    luassert.is.same({}, guard.check({ ".metrics" }))
  end)

  -- uml ir 的仓根 policy.edn 是生成物(ADR 0070 / #99):走 .gitignore 不入库,
  -- 推演写入库的 docs/architecture.proposals.edn。放行 policy.edn 即破此钉。
  it("test_generated_uml_policy_is_ignored_not_whitelisted", function()
    luassert.is.same({ "policy.edn" }, guard.check({ "policy.edn" }))
    luassert.is.same({}, guard.check({ "docs" }))
  end)

  -- crapper / mutator 只从模块根(最近的 .busted)取 busted 配置(#99),
  -- 位置由上游契约决定,入库的仓根配置必须放行。
  it("test_uml_busted_config_whitelisted", function()
    luassert.is.same({}, guard.check({ ".busted" }))
  end)

  -- 可选 pre-push hook(.githooks/)入库(#126),位置由 core.hooksPath 约定决定;
  -- CI 已删(.github/ 不再是合法根级条目),撤掉放行即破此钉。
  it("test_hooks_dir_whitelisted_and_ci_dir_rejected", function()
    luassert.is.same({}, guard.check({ ".githooks" }))
    luassert.is.same({ ".github" }, guard.check({ ".github" }))
  end)

  -- 常规根级条目不受影响。
  it("test_regular_entries_stay_whitelisted", function()
    local violations = guard.check({
      "src",
      "test",
      "AGENTS.md",
      "CODING_STANDARDS.md",
    })
    luassert.is.equal(0, #violations)
  end)

  -- 防回归:白名单不是摆设,未知根级条目必须仍被报违规。
  it("test_still_flags_unknown_root_entry", function()
    local violations = guard.check({ "mystery-root-file.txt" })
    luassert.is.equal(1, #violations)
    luassert.is.equal("mystery-root-file.txt", violations[1])
  end)

  it("test_deduplicates_repeated_names", function()
    local violations = guard.check({ "mystery.txt", "mystery.txt" })
    luassert.is.equal(1, #violations)
  end)
end)
