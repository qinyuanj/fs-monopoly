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
| 工具行为、CLI、PATH/env/subprocess 或工具契约 | `lua tools/cli.lua <子命令> --help` 与对应 `tools/**/test/**` |
| 宿主接口或真机行为 | `EggyAPI.lua` / `EggyEditorAPI.lua` 仅作第三方线索；当前适配器、对应测试与 [`docs/decisions.md`](docs/decisions.md) 才是项目真源 |
| 部署 | `tools/packages/ops/deploy.lua`、`tools/packages/ops/test/` 与 `lua tools/cli.lua deploy --help`；真机验收后、提交前跑只读的 `lua tools/cli.lua deploy-diff` |

## 验证路由

| 改动 | 先取窄反馈 | 收尾 |
|---|---|---|
| `src/**` | `lua tools/cli.lua spec-lane --profile test/behavior/<目录>`，或直接跑相关 spec | `lua tools/cli.lua verify` |
| `tools/**` | `lua tools/cli.lua spec-lane --profile tooling`；涉及 PATH/env/subprocess 时加 `verify --tooling` | `lua tools/cli.lua verify --tooling` |
| `test/**` | `lua tools/cli.lua spec-lane --profile test/<目录>` | `lua tools/cli.lua verify` |
| 只改叙事 Markdown | `lua tools/cli.lua spec-lane --profile test/guards`（含链接与 docs 白名单） | 无额外车道 |

按目录点跑写从仓根起的完整路径（如 `--profile test/behavior/ui`）；`--profile ui` 报 unknown profile。

入口统一写 `lua`（ADR 0083）：候选 `lua5.4` → `lua54` → `lua` → `lua.exe`，每个都以 `-v` 校验含「Lua 5.4」；`LUA54_BIN` 可覆盖。

push 前唯一硬地板是 slim：`lua tools/cli.lua verify`。

本仓没有 CI。可选本地拦截：`git config core.hooksPath .githooks` 启用 `.githooks/pre-push`（同跑 `verify`，`git push --no-verify` 单次跳过）。

按改动风险另选插件 `uml_crap` / `uml_mutate`（显式步骤，不是硬地板；ADR 0068 / 0082）。它们由 DSH 插件 `dsh-uml-viewer` 自带二进制在本机原生运行，CRAP/变异所需 Lua 环境（含 luacov）由插件负责，本仓不预检、不承载（ADR 0082 / 0083）。

## 平台保证边界（#96 / ADR 0083）

原生 Windows 是本仓唯一受支持的开发与工具链平台；WSL 与 macOS 不再在保证面内，非 Windows 一律判不可用。工具脚本经 Git for Windows / MSYS 的 `bash` 执行（发现不到 bash 判不可用）。

- 受控 Lua 环境（ADR 0072）缺失或版本越界是真实失败，退 1 并打印安装命令。
- 工具或平台不可用退 3，`verify` 把该车道标 `UNAVAILABLE` 并整体退 3（有真实失败则退 1），绝不退 0。看到退 3 先查环境再重跑，不要当测试回归排查；分类真源是 `tools/foundation/tool_availability.lua`。

## 操作边界

- 运行 `editor-cli` 的 `play start` / `play stop`（或 `EditorAPI.run_game` / `stop_game`）、模拟输入，或改动部署目录（含 `deploy`）前，每次单独说明要做的那一步并等待用户明确同意。「测试一下」「你跑吧」这类泛指授权只覆盖用户当时点名的那一步，不延伸到同轮其他部署或开关试玩。
- 新自动化脚本默认 bash；`deploy` 在原生 Windows 上直接取 `%USERPROFILE%` 并把 payload 经 `robocopy` 拷到 `%USERPROFILE%\Desktop\dev\eggy\LuaSource_大富翁`，不再经 `cmd.exe` / `wslpath` / `/mnt/c`（ADR 0083）；缺 Windows 原生工具退 3。
