# Agent 路由

**蛋仔派对大富翁** — Lua 5.4，清洁架构七层 + foundation，运行于 Eggy 宿主。

本文件是唯一任务入口。先定位下表命中的分支，再读取对应真源；不要为建立背景扫描整棵文档树。用中文回复。

## 任务路由

| 触发场景 | 真源 |
|---|---|
| 修改 `src/**` 或 `test/**` | [`CODING_STANDARDS.md`](CODING_STANDARDS.md)，再读目标模块与对应测试 |
| 领域词汇、对象命名或产品概念 | [`GLOSSARY.md`](GLOSSARY.md) |
| 模块归属、依赖方向或层边界 | [`docs/architecture.md`](docs/architecture.md) 的职责说明，再以 `tools/packages/arch_policy/levels.edn`（层序与同层分组唯一真源）、`tools/packages/arch_policy/policy.json`（其余规则）与 `test/guards/` 为执行真源（slim 的 guards 车道即层门禁） |
| 决策理由、已批准例外或 ADR | [`docs/decisions.md`](docs/decisions.md) |
| 工单登记、台账或 triage | [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)、[`docs/agents/triage-labels.md`](docs/agents/triage-labels.md) |
| 术语登记或领域模型维护 | [`docs/agents/domain.md`](docs/agents/domain.md) |
| 产品行为或配置 | `src/config/**`、对应 `src/**` 与 `test/behavior/**` |
| 工具行为、CLI、PATH/env/subprocess 或工具契约 | `tools/specs/*.prompt`、`lua5.4 tools/cli.lua <子命令> --help` 与对应 `tools/**/test/**` |
| 宿主接口或真机行为 | `EggyAPI.lua` / `EggyEditorAPI.lua` 仅作第三方线索；当前适配器、对应测试与 [`docs/decisions.md`](docs/decisions.md) 才是项目真源 |
| 部署 | `tools/packages/ops/deploy.lua`、`tools/packages/ops/test/` 与 `lua5.4 tools/cli.lua deploy --help` |

## 验证路由

| 改动 | 先取窄反馈 | 收尾 |
|---|---|---|
| `src/**` | `lua5.4 tools/cli.lua spec-lane --profile test/behavior/<目录>`，或直接跑相关 spec | `lua5.4 tools/cli.lua verify` |
| `tools/**` | `lua5.4 tools/cli.lua spec-lane --profile tooling`；涉及 PATH/env/subprocess 时加 `verify --tooling` | `lua5.4 tools/cli.lua verify --tooling` |
| `test/**` | `lua5.4 tools/cli.lua spec-lane --profile test/<目录>` | `lua5.4 tools/cli.lua verify` |
| 只改叙事 Markdown | 检查内部链接，并确认 docs 白名单 guard | 无额外车道 |

`--profile` 的具名车道只有 `behavior` / `tooling`；按目录点跑写从仓根起的完整路径（如 `--profile test/behavior/ui`），`--profile ui` 报 unknown profile。

入口统一显式写 `lua5.4`（ADR 0073）：本机 `lua` 是 5.1，兄弟仓依赖它，不改全局别名。

push 前唯一硬地板是 slim：`lua5.4 tools/cli.lua verify`。

本仓不跑 CI（2026-10-22 维护者决定，`.github/` 已删除）。可选本地拦截：`git config core.hooksPath .githooks` 启用 `.githooks/pre-push`（同跑 `verify`，`git push --no-verify` 单次跳过）。

按改动风险另选（都是显式步骤，不是硬地板）：`lua5.4 tools/cli.lua uml crap`、`lua5.4 tools/cli.lua uml mutate`；完整 flag 以 `lua5.4 tools/cli.lua verify --help` 与 `lua5.4 tools/cli.lua uml --help` 为准。

uml-viewer 质量入口（ADR 0068 / #93）：`lua5.4 tools/cli.lua uml check` 只做预检，`uml crap` / `uml mutate` 经邻接 `.uml-viewer/uml-viewer/scripts/uml_posix.py` 派发（`UML_VIEWER_TOOL_ROOT` 可指向兄弟仓开发树）。不要直接跑安装器拷到仓根的 `./uml`：它不钉 `LUA_PATH`，也不做受控 Lua 环境预检，模块可能从版本口径外的 tree 解析出来。契约见 `tools/specs/uml_quality.prompt`。

uml-viewer companion 边界（ADR 0070 / #99）：

- 仓根 `./uml` 只在 `lua5.4 tools/cli.lua uml view` 拉起的 companion 内可用（环境已钉死并沿启动链下传）；其他场合仍按上一段不作入口。
- companion 不改仓根 `policy.edn`（`uml ir` 的生成物）。维护者改层序或同层分组时编辑 `tools/packages/arch_policy/levels.edn`，改归属或其他边界时编辑组件策略与 guard；推演只写 `docs/architecture.proposals.edn`（只含 `:proposals` / `:omit`），再跑 `uml ir` 重生。
- companion 只改 `docs/architecture.proposals.edn` 与 `src/`；不得修改 `levels.edn` 或组件策略，不碰 git 远端、不关单。

## 平台保证边界（#96 / ADR 0073）

WSL Ubuntu 24.04 与 macOS 是受支持的开发平台；原生 Windows 只是部署目标（ADR 0073 取代 ADR 0066 / 0071，2026-10-27 增补 macOS）。`dry` 由邻接 `.uml-viewer/dryer` 承接并真实扫描（#148；检出与 venv 按契约手动准备，缺失退 3，有效结果须候选文件数 > 0 且新写出入库的 `.metrics/dry.edn`）。

- `tools/foundation/platform_boundary.lua` 保留平台声明与显式跳过的通用协议；保证面判定是 `supported_platform()`（`evaluate` 也经它判定），当前为 Linux（WSL 开发机）与 macOS。不可用（退 3）/ 显式跳过（退 0，`status=skipped`）/ 真实失败（退 1 或用法错误退 2）互相区分，跳过不计通过。
- 默认硬门禁不包含完整 dry 软车道；tooling 中相关探针实际执行。契约见 `tools/specs/dryer.prompt`。
- 测试与质量工具的 Lua 依赖只从**受控 Lua 环境**（`luarocks config rocks_trees` 解析的机器 tree，版本口径见 ADR 0072）装载。本仓只核对、不写入、不在项目内自举安装；缺失或版本越界是真实失败（退 1）并打印安装命令。工具/平台显式不可用（#96 / #112）沿用同一「不可用」：`spec-lane`、`behavior_parallel` 等入口退 3，stderr 打印 `status=unavailable tool=<名> step=<步>`，不跑测试、不计 failed；`verify` 把退 3 的车道标 `UNAVAILABLE`、计 `unavailable=K`，整体退 3（有真实失败则退 1），绝不退 0。看到退 3 先查环境再重跑，不要当测试回归排查。分类真源是 `tools/foundation/tool_availability.lua`。

## 操作边界

- 运行 `editor-cli` 的 `play start` / `play stop`（或 `EditorAPI.run_game` / `stop_game`）、模拟输入，或改动部署目录前，先说明并等待用户明确同意。
- 开发环境支持 WSL Ubuntu 24.04 与 macOS（ADR 0073）：Lua 5.4 与 LuaRocks 5.4 tree，入口显式写 `lua5.4`；新自动化脚本默认 bash，`cmd.exe` 只作为部署时取 `%USERPROFILE%` 的互操作面。Eggy 宿主位于 Windows 端，部署入口是 `lua5.4 tools/cli.lua deploy`（写入 `/mnt/c/...`，缺 `cmd.exe` / `wslpath` 退 3，macOS 上即如此）。
- `EggyAPI.lua` 与 `EggyEditorAPI.lua` 保持第三方边界，不把它们当作当前宿主契约。
