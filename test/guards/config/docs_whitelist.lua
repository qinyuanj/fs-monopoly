-- 项目叙事文档显式白名单。技能、工具契约、Gherkin 与上游资产由各自车道负责。

return {
  allowed_paths = {
    ["docs/agents/issue-tracker.md"] = true,
    ["docs/agents/triage-labels.md"] = true,
    ["docs/agents/domain.md"] = true,
    ["docs/architecture.md"] = true,
    ["docs/decisions.md"] = true,
  },
  retired_dirs = {
    "docs/inventory",
    "docs/reviews",
    "docs/superpowers",
    "docs/prototypes",
  },
}
