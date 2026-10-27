# 架构与放置原则

本项目采用七层 + foundation：

```text
L1 app
L2 host
L3 ui
L4 turn
L5 player | computer
L6 rules
L7 state | config
   foundation（唯一 substrate）
```

物理目录名、逻辑层名和 arch 组件名保持一致。层序与同层分组的唯一真源是 [`../tools/packages/arch_policy/levels.edn`](../tools/packages/arch_policy/levels.edn)；模块匹配、substrate、额外禁向规则和环豁免仍由 [`../tools/packages/arch_policy/policy.json`](../tools/packages/arch_policy/policy.json) 声明。`packages.arch_policy.load` 编译两份配置，`test/guards/lib/arch_policy_guard.lua` 执行完整边界；上图与本文只解释职责，不是层序真源。

门禁保留七层依赖方向、foundation 禁反向依赖整型层、未分类模块、每个命名空间视图的投影环，以及 UI 禁直接依赖 player/computer/rules、UI 禁依赖回合循环 `turn.loop`（回合循环调用 ui，锁输入谓词在 `state.input_lock`）、schema 纯度、ui.state 禁反向依赖 ui.coord。层号越大越内层，依赖只能指向同层或更内层。投影环把后代模块折叠成直接子节点再判定，不能只检查模块图；`allowed_cycles` 按 owning view、参与者集合和理由显式登记。

`packages.arch_policy.project_uml_policy(policy)` 直接投影加载后的层组，产生 uml-viewer 消费的 EDN；`lua5.4 tools/cli.lua uml ir` 把它与入库的 `docs/architecture.proposals.edn`（只含 `:proposals` / `:omit`）合并，写到仓根 `policy.edn`（gitignore，`:out` 为 `tmp/uml/fs-monopoly.edn`），不要另存一份可手改配置（ADR 0070 / 0077）。`:levels` 使用 `levels.edn` 的内层优先顺序（foundation、config/state、rules、computer/player、turn、ui、host、app），与门禁数字层号互逆；层配置缺失、非法或与组件策略不一致时，guard 与 IR 都失败且不回退。使用 uml-viewer 公共 IR 主入口 `uml-viewer.main.ir-generator <policy.edn> <out.edn>`；#93 接管安装与 CRAP/变异的用户命令 `lua5.4 tools/cli.lua uml <check|crap|mutate>`，#99 加上 `ir` 与 `view`（契约见 `tools/specs/uml_quality.prompt`）。IR 只表达图和层方向，禁向规则、未分类和投影环仍由本项目 guard 执行。

#92 在真实 policy/源码上验证：guard 与 uml-viewer IR 同为 570 模块、1788 内部依赖边，集合逐项相等，均无层违规。`require("src.host.init")` 沿用旧扫描口径作为外部依赖（模块 `.init` 折叠为 `src.host`）；另外两项外部依赖是 `Data.Prefab` 与 `Data.UIManagerNodes`。

## 放置原则

| 变化原因 | 放置位置 |
|---|---|
| 启动、装配、mixin 安装、跨边界接线 | `src/app` |
| Eggy 宿主对象与 API 适配 | `src/host` |
| 展示状态、输入路由、视图投影与渲染 | `src/ui` |
| 回合推进、等待、意图校验与输出编排 | `src/turn` |
| 玩家状态操作 / 中性电脑策略 | `src/player` / `src/computer` |
| 玩法判定与结算 | `src/rules` |
| 持久局面 / 静态内容与策略配置 | `src/state` / `src/config` |
| 无玩法语义的语言级工具与横切 port | `src/foundation` |

- 一个模块同时因业务规则和宿主/UI 细节而变化时，先拆边界，再放入对应层。
- port 跟随消费者命名：通用运行时契约在 `foundation/ports`，玩法契约在 `rules/ports`，局部回合 override 留在 `turn`。
- `app` 和 `host` 不拥有玩法规则；`foundation` 不持有游戏状态。
- UI schema 只描述节点、画布和布局；状态写入、输入路由与渲染分别留在所属视图。
- UI 内部由 `ui.state` 拥有展示状态与迁移，`ui.coord` 消费其结果并协调视图或宿主副作用；允许 `ui.coord` 依赖 `ui.state`，禁止 `ui.state` 反向依赖 `ui.coord`。
- 已批准的例外和不可由目录推导的边界见 [`decisions.md`](decisions.md)。
