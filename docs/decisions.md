# 决策登记簿

本登记簿只保留仍需独立解释的约束。编号沿用历史编号，不重排；过程和被取代方案由 Git 历史承担。

## ADR 0001 / 0002 — 七层、foundation 与 state 边界

采用 `app / host / ui / turn / player|computer / rules / state|config` 七层，`foundation` 是唯一 substrate。物理目录名、逻辑层名与 arch 组件名一致；`host` 的终态是 L2 宿主适配层。foundation 可被任意层依赖，但不依赖任何七层，也不含玩法语义。

state 只向 foundation 依赖。foundation 需要可变状态时暴露参数化纯算法，由状态持有层包装“取状态 + 调算法”；装配和 mixin 安装归 `src/app`，不为单点需求开反向依赖例外。

## ADR 0018 — 局内金币以角色 Fixed 属性为真源

局内金币唯一真源是角色 Fixed 属性 `coin_count`；不建立 `player.cash` 缓存或镜像。读写统一经 `src/player/actions/balance.lua`，规则层不直调宿主属性接口。金额只接受有限整数，余额不得为负；缺失属性、角色不可读写或写入失败都硬失败并可诊断。转账先验证双方能力与付款余额，再写双方，部分失败时尽力回滚。

## ADR 0029 — `src/ui/manager` 是 host-EUI adapter 例外

`src/ui/manager` 保留在 UI 层，承担宿主 EUI 节点镜像，因此可在 guard 明示豁免下直调 `GameAPI` / `LuaAPI`。例外不扩散到 UI 业务；业务查询仍走 port。若出现第二个同类子系统，或 manager 开始持有大量业务状态，重新评估归属。

## ADR 0030 — 无 debug/release 二分，日志常开

项目没有 debug/release 构建分叉；部署只复制 payload。logger 常开，测试静音由测试层注入；发布后排障以部署目录 `log.txt` 为证据。日志和调试能力仅在能定位发布异常时保留，纯开发探针连同专属测试一起删除。

## ADR 0038 — 道具窗口是局面快照

道具窗口打开时一次物化 options，存续期内局面冻结；每次合法变化经 `reopen_or_finish` 重建窗口。验收先铺局面再开窗，断言窗口打开时的 offer 面。若未来引入窗口存续期内的并行局面变化，必须重议本决策。

## ADR 0046 — 宿主调用以取证、端口和明确成功信号为准

已取证宿主签名采用单次直调，`pcall` 只防异常炸穿；成功按接口规定的明确信号判定，无返回值的宿主调用以可读回的状态翻转为准。宿主调用经外层 adapter/port 进入内层，业务规则不索引宿主方法。对象缺失、方法缺失、调用异常、状态未翻转与跳过分支必须各自留痕。宿主类名不稳定，逻辑不依赖 `type()` 名；API 注解只是线索，签名与返回值以真机证据为准。

**通用事实（2026-09-03，#610 取证）：宿主 API 参数错误不抛 Lua 异常**，只记一条 ERROR 日志并返回 nil，`pcall` 报告成功。所以「pcall 没抛」永远不是成功信号——这与 ADR 0065 登记的 `default_ports.end_game` 例外同型：那条例外之所以成立，只因 `game_end` 的成功信号真机尚未取证，取证后按本条收紧。

**取证结论修正（2026-09-03，#610，取代 #263 探针结论）**：宿主 `CampRole` 上**没有** `die`，`die` 在 `role.get_ctrl_unit()` 返回的单位（`LCharacter`）上；真实签名 `unit.die(dmg_unit?)`，单参可省、**不带 self**（冒号调用被宿主以 params count mismatch 拒收），且**无返回值**，成功只能以 `unit.is_die_status()` 由 false 翻 true 判定。#263 探针记录的 `role_type=table`、`role.die` 存在且返回真值，探到的是我们自己的合成 AI 角色适配器（Lua table，自带 `die` 并自行退役），不是宿主 Role；据此写下的「role 有 die、签名 `die(self, nil)`、成功按 truthy 返回值」对宿主 Role 三条全不成立，真人玩家破产时宿主 `die` 从未成功过。修复后 `src/host/role_die.lua` 按对象分两条路径：合成适配器仍按 truthy 返回值判定，宿主 Role 走控制单位并回读 `is_die_status`。**分派认 `is_synthetic_actor` 标志，不认 `die` 存在性**——后者正是 #263 误判的形状，宿主 Role 哪天长出 `die` 就会静默退回被证伪的判据；只有既无标志又无 `get_ctrl_unit` 的鸭子替身才回落到自带 `die`。

出局后的棋子移除调同一个宿主入口 `GameAPI.destroy_unit`，使两类玩家一致（`LCharacter` 有 `destroy`、无 `set_visible`，隐藏路径尚无取证手段）。取句柄的路子两侧不同但同源：合成 AI 退役读 `registry.env.GameAPI`，真人侧经 `src/host/units.lua` 读全局 `GameAPI`，而 `host_install` 正是用全局 `GameAPI` 填的 `ctx.env`。移除失败**不推翻**端口成功：出局语义由 `is_die_status` 承担，移除只是表现层收尾，失败留一条 warn。真机验证待办：若销毁真人控制单位触发宿主重生或镜头异常，退到隐藏路径并重新取证。

## ADR 0054 — 单进程整房间，可见性与授权分离

一个 Lua 进程服务整房间并逐席位渲染，不是每客户端一进程。`client_role` 是 UI 写作用域选择器，不是授权身份。可见性由目标席位和展示态计算；授权独立校验事件边界解析出的 `actor_role_id`，不得用 `current_player_id` 或上次点击者替代。多席位测试不伪造“本机角色”掩盖生产缺失条件。

## ADR 0059 — Agent-only 知识面与显式路径白名单

项目知识入口固定为 `AGENTS.md → 任务真源`。可执行代码、测试、配置、CLI 帮助和工具契约优先于叙事文档；`docs/` 只保留显式白名单中的五份 Markdown，不使用逐文件 front matter，不保留墓碑、兼容页、阶段报告或历史探索，Git 历史承担归档。

该决策取代历史 ADR 0003、0033、0056。新增长期知识先证明明确消费者、当前有效、没有更权威的可执行真源，且独立文件比并入现有真源更便宜；否则写入代码、测试、配置、工具契约或工单。技能、Gherkin、工具契约和上游资产各由自己的执行/同步边界管理，不并入项目叙事文档白名单。

## ADR 0060 — 行动日志显示窗口取机型容量保守下界

宿主运行时读不到字号、节点高度与分辨率（`Role.*` 只有 setter，`GameAPI.get_eui_*` 只取句柄；已全文核实 `EggyAPI.lua` / `EggyEditorAPI.lua`），ELabel 可视行数无法推导，任何按单一机型标定的行数上限都会在其他分辨率上失效。因此行动日志显示窗口取常量 `DISPLAY_LINE_LIMIT = 20`，语义是「最小支持机型也不溢出」的保守下界，不是「填满屏幕」；状态层仍保留完整历史。若宿主日后暴露可读尺寸/字号，或日志控件换成可滚动容器，重议本决策。

## ADR 0061 — 玩家控制语义的两轴模型与唯一模块

席位身份与控制模式是两个正交事实：补位电脑身份继续由 `player.is_ai` 表示，托管模式收敛为 `direct` / `manual_delegation` / `afk_delegation` 三态，以扁平字段 `player.control_mode` 保存。该字段只允许 `src/player/control.lua` 解释或修改；对外只有领域命令（`toggle_manual_delegation`、`enable_afk_delegation`）和窄查询（`is_replacement_computer`、`is_delegated`、`is_afk_delegated`、`is_computer_controlled`），模块本身不执行分享面板、广播或提示副作用。

「当前是否由电脑执行」只有 `is_computer_controlled` 一处派生语义：补位电脑身份或任一托管模式任一成立即为 true。规则层继续经既有 `auto_play_port` 查询，端口谓词更名为 `is_computer_controlled`；允许依赖玩家层的回合与电脑决策直接使用控制模块。UI 不依赖玩家层：回合输出侧物化不可变玩家控制快照（至少 `is_delegated` 与 `is_computer_controlled`），选择门控与托管特效消费同一快照。旧的 `auto` / `auto_source` / `ai` 字段与 `is_auto_player` / `by_ai` 标识一次性删除，不保留镜像或兼容层，并由架构 guard 阻止复现。分享面板锁存、AFK 超时计数与恢复提示节流仍归各自交互/回合流程，不属于控制模块。本决定遵循 ADR 0018 的唯一真源先例，并保持 ADR 0054 的本机角色可见性与行动者授权边界。

## ADR 0063 — 超时外壳退役：选择/弹层超时模块各自自持

`src/turn/waits/timeout.lua` 原是 choice 与 modal 两族超时的装配外壳：转发解析、合并 default_policy、经 `step_default_choice` / `step_modal_timeout` 两个出口步进。#602 将其整壳退役，理由有三：

1. **构造面虚胖**。ChoiceTimeout 构造器收 10 个依赖键，其中 `resolve_output_ports` / `deadline_service` / `resolve_choice` / `force_skip` 四个是全仓唯一实现的不变量，注入只会伪装可变性。收窄为 7 键后，不变量收进模块内部直 require，可覆盖面只剩真实策略点。
2. **幽灵依赖**。`resolve_choice_ui_state` 原先不在必填键里，缺了静默降级（`choice_ui_sync` 里的 type 守卫吞掉缺失），缺屏探测形同虚设。升格为必填键后，缺失在构造期即报错。
3. **外壳零增值**。`default_policy` 导出零生产调用，纯为测试存在；modal 半壳只剩一行转发。退役后 `step_choice_timeout` / `step_modal_timeout` 端口分别直挂 `ChoiceTimeout.step_default` 与 `modal_timeout.step_default`，`ui_sync` / `loop/ports` / `ui/ports/init` 的模块清单同步改指两个本源模块。

**modal 耦合评估结论（保留）**：choice_timeout 对 modal 的唯一耦合是 `_dispatch_action_with_close_choice`——超时派单前经 modal 端口收屏。这是「超时收屏」验收场景的承重路径，不是可剪的依赖方向问题，予以保留。

**测试通路随之切换**：不变量不可再注入，观测型测试改用仓库既有模块字段补丁通路（`with_patches` 替换 `src.turn.deadlines` 字段），输出端口经 `state.gameplay_loop_ports.output` 注入（与生产 `resolve_port` 路径一致）；min-visible 等策略钉改经公开 `step_default` 驱动默认装配，不再触碰策略表导出。

## ADR 0064 — 选择超时默认装配的 no-op 回落：三透传键与 modal 收屏缓存保留

#603 收尾 #602 的两处余留并钉 no-op 回落：验收车道的超时驱动态是裸 runtime state（`ensure_all` 不注入 `gameplay_loop_ports`），默认装配若在 ui_sync 端口缺位时直接调键会崩在 arm 帧。现三键全部带回落，缺端口不崩，超时自动代答/分阶段警告/收屏链路照常。

1. **ui_sync 三透传键保留（不收窄）**。`on_pending_choice` / `is_choice_active` / `resolve_choice_ui_state` 保持必填构造键与端口在场时的一比一委派；端口缺位时分别回落：arm 帧静默 no-op、`is_choice_active` 回落运行时待决、`resolve_choice_ui_state` 回落 `should_warn=false` gate。收窄不可行：生产路径端口恒在场，委派是真实行为而非虚胖注入；缺位回落只服务无端口车道，两者都由 `type(ports[key]) == "function"` 守卫切换。
2. **modal 收屏引用缓存保留（不逐次重建）**。`_dispatch_close_opts` 与 `_cached_dispatch_modal_ref` 按端口引用比较重绑，`on_close_choice` 在 `dispatch_action` 内同步消费（当次派单即读），共享表不会跨局残留，两局端口引用交替不串；每次重建无观测收益，予以保留。
3. **缺屏告警不在默认装配承担**。引擎步进只取 `active` 判定做跟踪清算，gate 回落的结果即弃（#523 注释）；缺屏探针与告警经生产 ui_sync 端口在 dirty 刷新后采样（#524 时序），默认装配的 `should_warn=false` 只保证裸车道不误报。

## ADR 0065 — 终局收尾：胜负标记后显式 game_end，终态事件不参与落地 hold 延迟

上线实测「游戏胜利不退出」暴露两个叠加断点，本 ADR 钉死修复决策与宿主时序约定：

1. **整局结束必须显式调用 `GameAPI.game_end()`**。宿主文档明示「胜利并不代表玩家将离开游戏，还需要设置游戏结束才会离开」，且「设置胜利或失败需要在结束之前」——时序为逐玩家 `game_win/game_lose_and_show_result_panel()` 标记（带面板）→ 最后一次 `game_end()`。此前全仓零调用，会话永不终止（与 #608 漏调 `request_archive` 同型缺口）。落地为 `runtime_ports.end_game` 端口 + `default_ports.end_game` 宿主直调（ADR 0046 留痕），由 `endgame_result_panels._finalize_game_result` 在面板路由后无条件调用；面板链任何一环断裂（面板方法抛错、`resolve_role` 抛错）都吞成 warn，不阻塞收尾。
2. **`gm.finished` 是终态事件，绕过落地视觉 hold 的 defer**。淘汰型胜利的 emit 天然落在 hold 激活窗口（`move_followup` 进 landing 前先 `hold.start`，结算淘汰后脚本泊在 `wait_landing_visual`），而 defer 的释放依赖 `advance_turn` 恢复脚本——`finished` 后 `advance_turn` 直接返回，release_pending 永不置位，回调永久滞留。`event_handlers._register_handler` 对 `monopoly_event.game.finished` 置 immediate 直派，其余事件 defer 语义不变。

已登记例外（#609 复审，2026-09-03 真机试玩后维持）：**`default_ports.end_game` 暂以「pcall 无异常」为成功**，偏离宿主调用第 3 条「成功按接口规定的明确信号判定」。理由：`game_end` 返回值仍未取证——真机试玩只观测到副作用（会话退出），没有读回返回值；宿主文档亦只述副作用。若其确无返回值，truthy 判定会把真实成功误报为失败。收紧的前提是单独探针读一次 `game_end` 的返回值，而非再跑一次试玩；在此之前本例外与上文「pcall 没抛不是成功信号」的通用事实并存，即本端口的 `true` 只代表「调用未炸」，不代表宿主已结束会话。

遗留嫌疑已由真机试玩排除（2026-09-03，#609 取证）：宿主事件回调三参签名假定 `(_, _, data)`、`gm.finished` 注册句柄被丢弃未校验（对照 #585 已证实宿主会静默拒注册）——真机胜负面板按玩家正确弹出且会话随即退出，说明句柄注册未被静默拒、`winner_ids` 也确实从第三参取到，整条 `gm.finished` → 面板 → `game_end` 链路端到端成立。两条嫌疑均按观测证据关闭，不再列为待办。

## ADR 0066 — 开发与工具链保证面收窄到原生 Windows

工具链的平台约束原为「macOS 与 WSL Ubuntu」（#127 / #129），Windows 只作为部署目标。本决策把保证面收窄为**原生 Windows 单一平台**：`foundation/{shell,proc,fs,env,path}` 不再保留 POSIX 路径，改以 Lua 标准库与 `cmd.exe`／原生可执行表达；`deploy` 的 WSL 互操作分支（`cmd.exe` + `wslpath`）与其测试一并退场。理由：Eggy 宿主、部署目标与开发机都在 Windows，保留一条没有消费者、却要为它各写一套测试的 POSIX 路径是纯负担；`tools/packages/ops/deploy.lua` 的双轨写法已证明原生等价实现可行，是本决策的现成模板。

`sh` / `find` / `rm` / `mkdir -p` / `cp -R` / `command -v` / `uname` / `pwd` / `/tmp` / 后台 `&` + `sleep` 的语义一律换为原生等价。**Git for Windows 的 POSIX 层不是受支持的运行前提**——`sh.exe` 与 MSYS 路径改写会让「兼容 Windows」退化成「兼容某个 Git Bash」。断言 POSIX 契约的既有测试改写为断言当前平台口径，使「在非 Windows 平台运行会红」成为显式事实，而不是靠注释里的约定。

代价必须写明：这是平台收窄而非双轨化，将来若回到 macOS 须重新引入平台分派层。后台并行执行（`parallel_lanes`）没有现成模板，实现形态在落地时单独取证。

本条中的 `cmd.exe` 不是对新自动化脚本形态的要求；脚本形态、hook 里 sh 的转发边界与 CI 取舍见 ADR 0071。

## ADR 0067 — 本仓退场本地 swarm-forge 编排

`swarmforge/` 的 pack 资产（conf / roles / constitution 共 12 个文件）整套下架，`.swarmforge/` 运行时状态不再由本仓定义；随之删除 AGENTS.md 的 swarm 路由行与 pack 同步纪律、`.gitignore` 的 swarm 段、`root_whitelist_guard` 的 `swarmforge` 白名单与 launcher 退役钉、`repo_hygiene` 的 `.swarmforge/` 违规项、`features/manifest.lua` 的 `features/swarmforge/*` 三条、`clean`/`distclean` 的 `.swarmforge/` 条目。启停、编排与角色供给不再由本仓承接。

APS 三件（`gherkin-parser` / `ir-dry-checker` / `gherkin-mutator`）的 PATH 供给机制同期整套删除：`provision.lua`、`swarm_root.lua`、`aps_forwarders.lua` 与其单测、`test/support/aps_forwarder_probe.lua` 一起退场，契约文本改为按显式路径调用 `tools/packages/acceptance/cli/parser.lua`、`cli/ir_dry.lua` 与 `acceptance_mutate/mutator.lua`。判据是按名解析在本仓**没有消费者**：唯一能成立它的前提是外部 launcher 把 `.swarmforge/bin` 放 PATH 最前，而本仓真实调用点早已是显式路径；为不存在的消费者保留转发器，还要在 Windows 上再养一套 `.cmd` 变体。

## ADR 0068 — 质量控制全量交接到 uml-viewer

CRAP、变异与架构图的生成整体移出本仓，交由 `qinyuanj/uml-viewer`（`lua` 分支）的标准派发承接：仓根以 `uml-quality.json` 声明 `standardTools`，CRAP 与变异经 `./uml crap` / `./uml mutate` 走 crapper / mutator 的 Lua 路径，架构面经 `./uml ir` 走 policy 与 IR。当时在 `tools/tools.lock` 里的 `crap4lua` / `mutate4lua` / `arch_view` 三钉、`tools/packages/{crap,mutate,coverage,arch_view}` 与对应 verify 车道随之退场。`docs/architecture.md` 与 `test/guards/` 仍是「人能读懂、机器能拦」的层边界执行真源，policy 是同一份边界在 uml-viewer 侧的表达式，不构成第二真源。

理由：uml-viewer 已占据「非 Clojure 的 CRAP 与变异」这一角色，具备 Lua 扫描与原生 Windows 复验记录；本仓的 `crap4lua` / `mutate4lua` 是同一角色的第二实现，`arch_view` 与它的架构面是同一件事的两套真源，留着即两套会漂移的真源。最后两个跟随上游主干的工具随后也退役：`dry4lua` 由 #148 改由 `qinyuanj/dryer` 承接，`acceptance4lua` 连同中文 Gherkin 验收管线由 #147 整体删除（母规格 #146）。两只工具退场后，整套「工具跟随上游主干」装载机制——`tools/tools.lock` 及其解析、HEAD 解析缓存、源码浅克隆与按锁安装——由 #149 一并删除。

落地（#93）：本仓的受支持入口是 `lua tools/cli.lua uml <check|crap|mutate>`，它在钉死 `LUA_PATH`/`LUA_CPATH` 的 cmd 批处理里调用同一个 `uml-command.ps1`，派发次序与 validResult（crap 0/2、mutate 0/3）仍由 uml-viewer 判定。安装器拷到仓根的 `./uml` / `uml.ps1` 被忽略，不作为入口：它们继承用户 `LUA_PATH`，不钉装载面、也不做受控 Lua 环境预检，工具可能从版本口径外的 tree 解析出来。`.metrics/` 按上游 README 入库：真实 `uml crap|mutate` 跑出的度量随改动提交（#69 维护者决定）。契约见 `tools/specs/uml_quality.prompt`。

## ADR 0069 — 测试框架的终态是 busted

本仓测试后端定为 busted，LuaUnit 与自研运行器退场。三项约束随决策一并钉死：

1. **迁移分两步，各自可独立验收**。先换断言层（`lu.*` → luassert），再换结构层（`TestX = {}` + `function TestX:test_y()` → `describe` / `it`）。**不做「自动把 TestX 包成 describe」的兼容层**：这类 shim 出错的表现是测试静默通过，是本仓最难发现的一类事故。两步之间的中间态允许进仓库。
2. **装载与调用不依赖可执行位**。busted 与 `luassert` / `say` / `lua_cliargs` / `mediator_lua` / `penlight` / `lua-term` / `luasystem` / `luafilesystem` / `dkjson` / `datafile` 从受控 Lua 环境（ADR 0072）装载，以 `lua -e 'require("busted.runner")()'` 形态调用，与 `lua54` 既有「不依赖 shell wrapper 或可执行位」口径同源；`luaunit` 的 ensure 随之退役。Windows 上 tree 布局与 POSIX 同形已取证，不需平台分支。
3. **完成的判据是数量与红绿双钉**。迁移前先在车道上取逐车道 passed / failed 基线，迁移后必须一致；另加 spec 文件集数量的 guard，防止文件被静默漏跑；再加一组故意写错的断言样本，迁移后仍须为红——直接钉住「断言没有退化成恒真」，这是九千处机械替换的真实风险面。

理由：本仓今天并存两套 harness——`test/**` 走 LuaUnit 类风格，`features/**` 的生成物已是 `describe` / `it` 加自带 harness（上游 generator 天然输出 busted 形状）。迁到真 busted 把两者统一成一套，并让 crapper / mutator 的 Lua 默认路径（busted + luacov）不必再包一层适配；此前替换掉 busted 的决定没有留下任何登记，本决策取代之。

## ADR 0070 — uml-viewer 可视化接入：生成式 policy 与 companion 环境钉死

接入 uml-viewer 的图窗与 companion 时，两件事按本仓口径而非上游默认处理：

1. **policy 是生成物，推演另存**。仓根 `policy.edn` 由 `lua tools/cli.lua uml ir` 从 `arch_policy.project_uml_policy` 投影生成、不入库；上游 policy 中唯一需要人手维护的 `:proposals` 与 `:omit` 存于入库的 `docs/architecture.proposals.edn`，生成时合并。companion 不得直接改写 `policy.edn`：层序或归属不对，改 `docs/architecture.md` 与 guard；推演只写覆盖文件，再经 `uml ir` 重生。
2. **companion 继承钉死的环境**。图窗只经 `lua tools/cli.lua uml view` 启动，它在调用上游启动器前钉死 `LUA_PATH` / `LUA_CPATH`；Herdr 由上游从继承的 PATH 中选取（>= 0.9.3、protocol 22 的最高版），本仓不钉版本、不改 PATH 次序。上游每次全新启动都为本项目新建 Herdr server，环境沿启动链原样下传到 companion 及其子 shell，`--restart` 与崩溃恢复复用同一 server；因此仓根 `./uml` 在该 companion 内可用，在其他场合仍按 ADR 0068 不作入口。

理由：上游 policy 是单个 EDN 文件、不支持引用，companion 的系统提示要求它「写或更新 policy」——照做即生成与 `docs/architecture.md` 并行漂移的第二真源；而每次重生又会冲掉 `:proposals`，所以只把推演拆出。上游提示词硬编码 `./uml crap|mutate|ir`，仅靠 AGENTS.md 让 companion 改用 `lua tools/cli.lua uml` 会与系统提示冲突、遵从不可预期；在入口处钉环境让上游命令本身变对。上游 `c714f83` 起 Herdr 由精确 0.9.3 放宽为 PATH 上 >= 0.9.3 的最高版，此前「0.9.3 局部置前」的做法会与用户已装的新版并存而让上游选取失败，故撤除；预检只按同口径确认 PATH 上至少有一个达标版本，不改全局 Herdr，也不改只读的上游检出。companion 以 `--dangerously-skip-permissions` 运行，维护者接受，并以 AGENTS.md 限定其边界：只改覆盖文件与 `src/`，不动 git 远端、不关单。

## ADR 0071 — 原生 Windows 自动化脚本形态与 CI 车道口径

仓库内新增或改写的自动化脚本与 CI 步骤默认用 `pwsh` / `.ps1`（GitHub Actions 走 `shell: pwsh`），不使用 PowerShell `Start-Job`；后台或并行执行按原生进程语义表达。ADR 0066 的 `cmd.exe` 约束指 Lua 工具与原生子进程的**表达口径**（foundation 不保留 POSIX 路径，子进程按 `cmd.exe`／原生可执行调用），不要求新自动化脚本继续写 `.cmd`。

Git for Windows 用自带 `sh` 唤起 hook，这是宿主强制的启动边界，不是业务实现：hook 中的 sh 只允许定位仓根（定位失败可立即退出）并以 `exec lua tools/cli.lua verify` 形态转交原生 Lua 解释器；对工具结果的退出码分支、提示与业务逻辑一律归原生侧。当前 `.githooks/pre-push` 即此形态，因此 hook 存在 sh 文件不违反 ADR 0066 的「Git for Windows POSIX 层不是受支持运行前提」：sh 不承载业务逻辑，也不被当作可复用的运行时。

CI 只跑硬地板 slim `verify`；`verify --tooling` 是改 `tools/**` 时的本地叠加车道，不进 CI。退 3（平台/工具不可用）保持失败结论、仍为红灯，同时在 annotation 与 step summary 标 `UNAVAILABLE`，语义是「环境不可用，应重跑或补齐环境」而非「测试回归，应排查」。

理由：`cmd.exe` 是 Lua 工具与子进程的语义约束，不是脚本形态约束；Git for Windows 起 hook 必须经过 sh，但这一层不承载逻辑；CI 取舍与退 3 语义若无登记，只能从工单评论或 PR 叙述里反推。

## ADR 0072 — 退役项目工具缓存，测试与质量工具改用受控 Lua 环境

整套项目内工具缓存（原仓内工具 tree）与「工具跟随上游主干」装载机制退役（母规格 #146）。测试与质量工具唯一允许的 Lua 装载来源改为**受控 Lua 环境**：由 `luarocks config rocks_trees` 解析出的机器 LuaRocks 5.4 包树，版本口径为 busted `>=2.3.0,<3`、luassert `>=1.9.0,<2`、luacov `>=0.17.0,<1`、luacov-reporter-lcov `>=0.2,<1`、luacheck `>=1.2.0,<2`。本仓只核对、不写入、不在项目内自举安装 rock；不满足即真实失败（退 1）并打印可直接执行的安装命令。

落实口径：

1. **单一预检**。`tools/foundation/lua_env.lua` 是 tree 根解析、版本核对与模块来源校验的唯一实现。`preflight` 依次调 `luarocks config rocks_trees` 与 `luarocks list <name> --porcelain`，不调 `install` / `make` / `remove`。
2. **测试运行器**。`tools/packages/test_runner/runner.lua` 先预检，再把受控 tree 的 share/lib 路径接入本进程；`cache_loader` 只从这些 tree 装载 busted 及依赖，解析到 tree 之外（含 C 模块）即失败，未验证的 `package.loaded` 预注入同样失败。项目内不再有 `ensure_*_tree` 安装入口。
3. **变异 worker**。worker 的搜索模板只允许指向 worker 自身与受控 tree；模板指向其他 tree、源仓库代码、外部路径、路径穿越或空模板均失败。worker 不安装、不复制、不链接任何 rocks tree，`lfs` 校验器也从受控 tree 的 C 路径装载。
4. **uml 子进程**。`uml` 预检把每个受控 tree 的 `share/lua/5.4` 与 `lib/lua/5.4` 写进子进程的 `LUA_PATH(_5_4)` / `LUA_CPATH(_5_4)`（另加仓根），模块探针按同一组根判定来源；`./uml` 安装器拷贝仍不是入口，因为它不钉装载面、也不做预检。
5. **清理边界**。项目工具缓存路径从 bootstrap、package_path_helper、`.gitignore`、`clean` / `distclean` 与 uml 契约文本中移除；`distclean` 与 `clean` 同义。spec_lane 的实测时长缓存移到仓内 `tmp/`（gitignored，由 `clean` 清理）。

代价与边界：worktree 不再需要复制或冷装缓存，并发写坏共享缓存的问题随之消失；换来的是每台开发机/CI 必须自行提供满足口径的机器 tree（CI 的供给在 `.github/scripts/setup-lua.ps1`：构建完 LuaRocks 后预装五个钉定 rock）。缺失或版本越界是真实失败，不再归类为「网络不可用」；退 3 只保留给平台/工具显式不可用。真身校验不因缓存退役而放宽：模块来源、版本、worker 绑定与 uml 探针仍在每次运行时核对。
