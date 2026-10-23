---
name: device-debug
description: 真机运行时取证：分析部署目录 log.txt 定位异常，或经 editor-cli 驱动运行中的编辑器（查状态/读日志/远程执行 Lua/截图/插桩复现/查官方文档与 API）。触发：分析日志、排查发布后异常、真机验证、复现 UI bug、查 EUI 节点、查宿主文档，或用户提到 "debuglog"、"editor-cli"、"真机调试"、"19836"。
---

# 真机调试

运行时地面事实只有一个来源：部署目录。两条取证入口——事后读 `log.txt`，或经 editor-cli 与运行中的编辑器实时回路——共享同一套现场纪律。

## 现场事实

- **部署目录**：`/mnt/c/Users/<user>/Desktop/dev/eggy/LuaSource_大富翁/`（WSL 路径；Windows 侧仍是 `%USERPROFILE%\Desktop\dev\eggy\LuaSource_大富翁\`），由 `lua5.4 tools/cli.lua deploy` 从 WSL 纯拷贝生成，不是 git clone。`log.txt` 在根部。编辑器试玩直接加载目录里的 Lua 源码——**改文件即生效（下次启动试玩）**，这就是插桩通道。
- **editor-cli**：用 `/mnt/c/Users/<user>/.eggitor/cli/editor-cli.exe`（0.20.x，原生 Windows 可执行，从 WSL 经互操作直接调用；`env-res list` 查版本，`env-res update editor_cli_win` 升级）。`/mnt/c/FeverApps/party_pc/bin/editor-cli.exe` 是随客户端装的 0.4.0 旧版，命令面不同，不用它。连接自动发现编辑器实例，不必指定端口；`status` 连不上 = 编辑器没启动或没开 editor-cli，提示用户开，`doctor` 给完整只读诊断。
- **授权分层**：只读命令（`status` / `log *` / `screenshot` / `docs search` / `api *` / 只返回或只打印的 `exec`、日志分析脚本）直接跑。部署目录改动、改存档或改场景的 `exec`、`input *` 逐次授权：先说明影响与回滚方式，等用户明确同意；未获同意时保留现场。
- **试玩交接：用户开关，agent 观察**。准备就绪后提示用户开启或结束试玩，只用只读 `status` 等状态翻转（约 10–20s）；确需代跑 `play start` / `play stop` 时，逐次说明并等用户明确同意。中断或用户暂未操作时，如实报告当前状态并等待。
- **真人操作先协调**：需要点槽位、切回合或开第二个客户端时，先确认用户在场且愿意配合。优先设计自动化路径——试玩态 `game_execute` 能 `require` 任何模块、直调裁定入口、`inventory.give` 造状态、`print` + 截图取证；实在只能靠手点的（如 UI 事件 payload 的真实内容），如实说明这条自动化验不了。

## 入口一：log.txt 事后取证

用户给了日志路径或部署根目录就传参；否则裸跑脚本，由它兜底解析 `MONOPOLY_DEPLOY_TARGET` 或默认部署目录。

1. 跑分析脚本：

```bash
.agents/skills/device-debug/scripts/analyze_log.sh [-t 部署根] [-l log.txt路径]
```

脚本自身按 `-l` > `-t` > `MONOPOLY_DEPLOY_TARGET` > `cmd.exe` + `wslpath` 解析的 `%USERPROFILE%` 顺序找部署目录，与 `deploy` 同一口径；不在 WSL 里（拿不到 Windows 家目录）退 3。

2. 读输出：TOP_MATCHES 已按严重度排序（stack traceback > error > attempt/nil value > failed/exception/panic > warn）；`[warn]` 只在和用户反馈直接相关时深入。
3. 追源码只看命中文件和相邻调用点，不预读整目录。
4. **完成标准**：收敛到 1–3 个最关键的异常或警告并给出证据行；或明确"未发现崩溃证据"，只保留关键警告与最近运行轨迹。

已知噪音：`[warn] board_feedback play_sfx_by_key ... cue_name=nil ... with_sound=false` 默认视为非致命声音告警，除非用户问题就是音效异常。脚本只给关键词命中与尾部日志；最终结论由你结合用户症状归纳。

## 入口二：editor-cli 实时回路

### 命令面

```bash
cd /mnt/c/Users/<user>/.eggitor/cli
./editor-cli.exe status                   # running / edit_mode / in_game_runtime / editor_state / 地图名
./editor-cli.exe exec "return <expr>"     # 编辑态同步求值，直接回显返回值
./editor-cli.exe log tail --lines 50      # 读编辑器日志文件（游戏 print 与 EditorAPI.log 都进这里）
./editor-cli.exe log grep <regex>         # 按唯一标记取回 print 输出；log trace 出某次试玩的结构化报错
./editor-cli.exe screenshot editor|game   # 打印 png 的 Windows 路径
./editor-cli.exe play start|stop          # 需逐次授权
./editor-cli.exe docs search "<问题>" --docset manual|game-api|editor-api --limit 3
./editor-cli.exe api search|get <名>      # 运行时 API 实时 meta；编辑态用 search-editor|get-editor
```

日志按文件读，不需要清缓冲；每次取证用唯一标记（`DEBUG-xxxx`）配 `log grep`，旧日志不会混进来。`exec` 报错以非零退出码返回并附堆栈。

`docs search` 默认文档集可能被自动判成帧同步（fs-manual）；本项目是 SE 地图，显式写 `--docset manual` 或 `game-api`。文档条目多数没有来源 URL，结论要以真机探针复核。

### 两种状态，两套 API

**编辑态（Edit Mode）**：直接调 `EditorAPI.*`（参考面：仓库根 `EggyEditorAPI.lua`，或 `api get-editor`），`return` 取值。
- EUI 节点：`get_eui_node_ids_by_name(name)` → id 列表；`get_eui_node_parent/children/type/attr`、`set_eui_node_attr`、`set_eui_node_parent`（可 reparent）。
- **node_id 是字符串**（打印出来像整数）：跨 exec 传递别写 int 字面量（会 `param 1 type mismatch`），每次 `get_eui_node_ids_by_name(...)[1]` 现取。
- 属性名用这套：`pos` / `size` / `anchor`（表，取 `.x/.y`）/ `visible` / `scale` / `rotation` / `opacity` / `name`；`position` 之类猜错了返回 nil。
- 截图：`screenshot editor|game` 打印 `C:/FeverApps/party_pc/Documents/editor_cli_screenshots/*.png`，换成 `/mnt/c/FeverApps/...` 直接 Read 看图。

**试玩态（In Game Runtime）**：游戏内代码一律经 `exec "EditorAPI.game_execute([[<lua>]])"`，跑在游戏 Lua 环境——可 `require` 部署目录任何模块，可访问 `UIManager` / `GameAPI` 等全局；真实 state 用 `require('src.app').init()` 取（已初始化时返回同一份）。`game_execute` 不回传值：游戏内 `print('DEBUG-xxxx ...')`，再 `log grep DEBUG-xxxx` 读回。`exec --runtime server|client` 在本地图报 `no active playtest server session`，不可用。

### 沙盒坑

- 编辑态没有 `pairs`（`for k,v in pairs(t)` 直接炸），表内容按已知字段名取；试玩态没有 `debug` 库。
- 双层字符串嵌套时内层一律用 `[[...]]`，避开 shell/Lua 引号转义地狱。
- 编辑态改属性（如 `visible`）不一定持久，停试玩后可能回弹；reparent 持久但要在编辑器里保存地图才落盘。运行时默认状态防御写进仓库代码（如启动时统一压灭），不依赖编辑器默认值。

### 复现回路

1. **插桩**：获得部署目录改动授权后，把仓库文件拷入部署目录，注入 `require("src.foundation.log").info_unlimited("[DEBUG-xxxx] ...")`（tag 唯一，方便清理），`luac -p` 过语法。
2. **起局**：提示用户开启试玩，轮询 `status` 直到 `in_game_runtime True`。
3. **触发**：等自然触发（大富翁回合自动推进），或 `game_execute` 直调目标模块（用桩 game 表隔离依赖）。
4. **取证**：后台轮询 `log grep DEBUG-xxxx` 直到命中（命中即退出拿一次通知），别前台 sleep；要视觉证据就在命中时立刻 `screenshot game` 并 Read 看图。
5. **清理**：提示用户结束试玩并轮询确认翻回编辑态；部署目录从仓库原样拷回，全目录搜 `DEBUG-xxxx` 确认无残留；提醒用户编辑器内的结构改动要保存地图。

## 输出约定

汇报区分三类证据：日志直接证明的、截图证明的、由上下文推断的。给出实际读取的日志路径或用到的取证命令与截图路径、最关键的 1–3 个发现、下一步最小修复建议。

## 真源

- editor-cli 官方文档：https://u5-creator.s3.game.163.com/manual/pc_md/editor_cli.html；离线命令参考 `editor-cli help detail <命令>`
- 编辑态 API 参考面：`EggyEditorAPI.lua`（仓库根）
- 部署：`lua5.4 tools/cli.lua deploy --help` 与 `tools/packages/ops/deploy.lua`
