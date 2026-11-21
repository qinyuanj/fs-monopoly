-- 项目叙事文档显式白名单。技能、工具契约、Gherkin 与上游资产由各自车道负责。

return {
  allowed_paths = {
    ["docs/agents/issue-tracker.md"] = true,
    ["docs/agents/triage-labels.md"] = true,
    ["docs/agents/domain.md"] = true,
    -- 客户端本地 API（Terminal API）实地核查记录：官方无独立文档，事实以本机实测落盘。
    ["docs/host/terminal-api.md"] = true,
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
