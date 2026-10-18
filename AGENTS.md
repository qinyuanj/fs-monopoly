# Agent 路由

**蛋仔派对大富翁** — Lua 5.4，清洁架构七层 + foundation，运行于 Eggy 宿主。

本文件是唯一任务入口。先定位下表命中的分支，再读取对应真源；不要为建立背景扫描整棵文档树。用中文回复。

## 任务路由

| 触发场景 | 真源 |
|---|---|
| 修改 `src/**` 或 `test/**` | [`CODING_STANDARDS.md`](CODING_STANDARDS.md)，再读目标模块与对应测试 |
| 领域词汇、对象命名或产品概念 | [`GLOSSARY.md`](GLOSSARY.md) |
| 模块归属、依赖方向或层边界 | [`docs/architecture.md`](docs/architecture.md)，再以 `tools/packages/arch_policy/policy.json` 与 `test/guards/` 为执行真源（slim 的 guards 车道即层门禁） |
| 决策理由、已批准例外或 ADR | [`docs/decisions.md`](docs/decisions.md) |
| 工单登记、台账或 triage | [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md)、[`docs/agents/triage-labels.md`](docs/agents/triage-labels.md) |
| 术语登记或领域模型维护 | [`docs/agents/domain.md`](docs/agents/domain.md) |
| 产品行为、验收场景或配置 | `features/**/*.feature`、`src/config/**`、对应 `src/**` 与 `test/behavior/**` |
| 工具行为、CLI、PATH/env/subprocess 或工具契约 | `tools/specs/*.prompt`、`lua tools/cli.lua <子命令> --help` 与对应 `tools/**/test/**` |
| 宿主接口或真机行为 | `EggyAPI.lua` / `EggyEditorAPI.lua` 仅作第三方线索；当前适配器、对应测试与 [`docs/decisions.md`](docs/decisions.md) 才是项目真源 |
| 部署 | `tools/packages/ops/deploy.lua`、`tools/packages/ops/test/` 与 `lua tools/cli.lua deploy --help` |

## 验证路由

| 改动 | 先取窄反馈 | 收尾 |
|---|---|---|
| `src/**` | `lua tools/cli.lua spec-lane --profile <目录>`，或直接跑相关 spec | `lua tools/cli.lua verify` |
| `tools/**` | `lua tools/cli.lua spec-lane --profile tooling`；涉及 PATH/env/subprocess 时加 `verify --tooling` | `lua tools/cli.lua verify --tooling` |
| `test/**` | `lua tools/cli.lua spec-lane --profile <目录>` | `lua tools/cli.lua verify` |
| `features/**` | `lua tools/cli.lua acceptance` | `lua tools/cli.lua verify`；行为变更再跑 acceptance |
| 只改叙事 Markdown | 检查内部链接，并确认 docs 白名单 guard | 无额外车道 |

push 前唯一硬地板是 slim：`lua tools/cli.lua verify`。

CI（#126）：`.github/workflows/verify.yml` 在原生 Windows runner 上跑同一 slim `verify`（不含 `--tooling`），job 名 `verify` 供维护者在 branch protection 里配置为 PR 必过检查；退 3 在 annotation 与 step summary 标 `UNAVAILABLE`，重跑即可。可选本地拦截：`git config core.hooksPath .githooks` 启用 `.githooks/pre-push`（同跑 `verify`，`git push --no-verify` 单次跳过）。

按改动风险另选（都是显式步骤，不是硬地板）：`lua tools/cli.lua uml crap`、`lua tools/cli.lua uml mutate`、`lua tools/cli.lua acceptance`、`lua tools/cli.lua acceptance-mutate`；完整 flag 以 `lua tools/cli.lua verify --help` 与 `lua tools/cli.lua uml --help` 为准。

uml-viewer 质量入口（ADR 0068 / #93）：`lua tools/cli.lua uml check` 只做预检，`uml crap` / `uml mutate` 经邻接 `.uml-viewer/` 派发。不要直接跑安装器拷到仓根的 `./uml`：它不钉 `LUA_PATH`，会从全局 luarocks tree 解析出假绿。契约见 `tools/specs/uml_quality.prompt`。

uml-viewer companion 边界（ADR 0070 / #99）：

- 仓根 `./uml` 只在 `lua tools/cli.lua uml view` 拉起的 companion 内可用（环境已钉死并沿启动链下传）；其他场合仍按上一段不作入口。
- companion 不改仓根 `policy.edn`（`uml ir` 的生成物）。层序或归属不对，改 `docs/architecture.md` 与 guard；推演写 `docs/architecture.proposals.edn`（只含 `:proposals` / `:omit`），再跑 `uml ir` 重生。
- companion 只改 `docs/architecture.proposals.edn` 与 `src/`；不碰 git 远端、不关单。

## 平台保证边界（#96 / ADR 0066）

原生 Windows 是唯一受支持的开发平台。`dry` 由邻接 `.uml-viewer/dryer` 承接并真实扫描（#148；检出与 venv 按契约手动准备，缺失退 3，有效结果须候选文件数 > 0 且新写出入库的 `.metrics/dry.edn`），`acceptance-mutate` 支持真实 worker job 与变异统计（#123）。

- `tools/foundation/platform_boundary.lua` 保留平台声明与显式跳过的通用协议；当前无 POSIX 专用能力。不可用（退 3）/ 显式跳过（退 0，`status=skipped`）/ 真实失败（退 1 或用法错误退 2）互相区分，跳过不计通过。
- 默认硬门禁不包含完整 dry / acceptance-mutate 软车道；tooling 与 acceptance 中相关探针实际执行。契约见 `tools/specs/dryer.prompt` 与 `tools/specs/acceptance4lua.prompt`。
- 工具自举的网络/下载类失败（#112：解析上游 HEAD、拉源码、luarocks 构建/安装时下载失败）沿用同一「不可用」：`spec-lane` 与 `behavior_parallel`（含 test runner 自举 busted，#131：contract/guards/behavior/tooling 等 busted 车道同口径）、`lint` 与 acceptance 面入口（`lua tools/cli.lua acceptance` 的 regenerate 步骤、显式 parser/generator/ir_dry 入口，#114）退 3，stderr 打印 `status=unavailable tool=<名> step=<步>`，不跑测试、不计 failed；`verify` 把退 3 的车道标 `UNAVAILABLE`、计 `unavailable=K`，整体退 3（有真实失败则退 1），绝不退 0。看到退 3 先查网络再重跑，不要当测试回归排查；锁文件缺项、上游仓库不存在、编译/构建错误与认不出的报错仍退 1。分类真源是 `tools/foundation/tool_availability.lua`。

## 操作边界

- 运行 `editor-cli` 的 `run_game`、`stop_game`、`clear-logs`，或改动部署目录前，先说明并等待用户明确同意。
- 开发环境只支持原生 Windows（ADR 0066）：Lua 5.4 与 LuaRocks 5.4 tree；`cmd.exe` 只约束 Lua 工具与原生子进程的表达口径，新自动化脚本形态与 hook 的 sh 转发边界见 ADR 0071。不依赖 WSL、Git Bash、Node 或 PowerShell Start-Job。Eggy 宿主位于 Windows 端。部署入口是 `lua tools/cli.lua deploy`。
- `EggyAPI.lua` 与 `EggyEditorAPI.lua` 保持第三方边界，不把它们当作当前宿主契约。
