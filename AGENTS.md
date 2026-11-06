# Agent 路由

**蛋仔派对大富翁** — Lua 5.4，清洁架构七层 + foundation，运行于 Eggy 宿主。

本文件是唯一任务入口：先定位下表命中的分支，只读该分支的真源。用中文回复。

## 任务路由

| 触发场景 | 真源 |
|---|---|
| 修改 `src/**` 或 `test/**` | [`CODING_STANDARDS.md`](CODING_STANDARDS.md)，再读目标模块与对应测试；写测试时调用全局 `tdd` skill |
| 领域词汇、对象命名或产品概念 | [`GLOSSARY.md`](GLOSSARY.md) |
| 模块归属、依赖方向或层边界 | [`docs/architecture.md`](docs/architecture.md)；执行真源是 `tools/packages/arch_policy/` 与 `test/guards/` |
| 决策理由、已批准例外或 ADR | [`docs/decisions.md`](docs/decisions.md) |
| 工单登记、台账或 triage | [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)、[`docs/agents/triage-labels.md`](docs/agents/triage-labels.md) |
| 术语登记或领域模型维护 | [`docs/agents/domain.md`](docs/agents/domain.md) |
| 产品行为或配置 | `src/config/**`、对应 `src/**` 与 `test/behavior/**` |
| 工具行为、CLI、PATH/env/subprocess 或工具契约 | `lua5.4 tools/cli.lua <子命令> --help` 与对应 `tools/**/test/**`；包内有 `CONTRACT.md` 时一并读（如 `tools/packages/uml_quality/CONTRACT.md`） |
| 宿主接口或真机行为 | `EggyAPI.lua` / `EggyEditorAPI.lua` 仅作第三方线索；当前适配器、对应测试与 [`docs/decisions.md`](docs/decisions.md) 才是项目真源 |
| 部署 | `tools/packages/ops/deploy.lua`、`tools/packages/ops/test/` 与 `lua5.4 tools/cli.lua deploy --help`；真机验收后、提交前跑只读的 `lua5.4 tools/cli.lua deploy-diff` |

## 验证路由

| 改动 | 先取窄反馈 | 收尾 |
|---|---|---|
| `src/**` | `lua5.4 tools/cli.lua spec-lane --profile test/behavior/<目录>`，或直接跑相关 spec | `lua5.4 tools/cli.lua verify` |
| `tools/**` | `lua5.4 tools/cli.lua spec-lane --profile tooling`；涉及 PATH/env/subprocess 时加 `verify --tooling` | `lua5.4 tools/cli.lua verify --tooling` |
| `test/**` | `lua5.4 tools/cli.lua spec-lane --profile test/<目录>` | `lua5.4 tools/cli.lua verify` |
| 只改叙事 Markdown | `lua5.4 tools/cli.lua spec-lane --profile test/guards`（含链接与 docs 白名单） | 无额外车道 |

按目录点跑写从仓根起的完整路径（如 `--profile test/behavior/ui`）；`--profile ui` 报 unknown profile。

入口统一显式写 `lua5.4`（ADR 0073）：本机 `lua` 是 5.1，兄弟仓依赖它，不改全局别名。

push 前唯一硬地板是 slim：`lua5.4 tools/cli.lua verify`。

本仓没有 CI。可选本地拦截：`git config core.hooksPath .githooks` 启用 `.githooks/pre-push`（同跑 `verify`，`git push --no-verify` 单次跳过）。

按改动风险另选 `lua5.4 tools/cli.lua uml crap` / `uml mutate`（显式步骤，不是硬地板；ADR 0068）。质量入口只走 `lua5.4 tools/cli.lua uml ...`，不直接跑安装器拷到仓根的 `./uml`：它不钉 `LUA_PATH`，也不做受控 Lua 环境预检。补充契约见 `tools/packages/uml_quality/CONTRACT.md`。

uml-viewer companion 边界（ADR 0070 / #99）：

- 仓根 `./uml` 只在 `lua5.4 tools/cli.lua uml view` 拉起的 companion 内可用（环境已沿启动链钉死）。
- companion 的写面只有 `src/` 与 `docs/architecture.proposals.edn`（只含 `:proposals` / `:omit`，改完跑 `uml ir` 重生 `policy.edn`）。`policy.edn` 是生成物；`levels.edn`、组件策略、git 远端与关单都留给维护者。

## 平台保证边界（#96 / ADR 0073）

WSL Ubuntu 24.04 与 macOS 是受支持的开发平台；原生 Windows 只是部署目标。`dry` 的安装与有效结果见 `lua5.4 tools/cli.lua dry --help`，使用口径见 `CODING_STANDARDS.md`。

- 受控 Lua 环境（ADR 0072）缺失或版本越界是真实失败，退 1 并打印安装命令。
- 工具或平台不可用退 3，`verify` 把该车道标 `UNAVAILABLE` 并整体退 3（有真实失败则退 1），绝不退 0。看到退 3 先查环境再重跑，不要当测试回归排查；分类真源是 `tools/foundation/tool_availability.lua`。

## 操作边界

- 运行 `editor-cli` 的 `play start` / `play stop`（或 `EditorAPI.run_game` / `stop_game`）、模拟输入，或改动部署目录（含 `deploy`）前，每次单独说明要做的那一步并等待用户明确同意。「测试一下」「你跑吧」这类泛指授权只覆盖用户当时点名的那一步，不延伸到同轮其他部署或开关试玩。
- 新自动化脚本默认 bash；`cmd.exe` 只用于部署时取 `%USERPROFILE%`。Eggy 宿主在 Windows 端，`deploy` 写入 `/mnt/c/...`，缺 `cmd.exe` / `wslpath` 退 3（macOS 上即如此）。
