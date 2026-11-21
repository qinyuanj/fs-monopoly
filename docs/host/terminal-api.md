# Terminal API（玩家操作台）参考

> 状态：2026-11-19 核查。官方手册**有**专门章节（标注为实验特性）：
> https://u5-creator.s3.game.163.com/manual/pc_md/lua/lua_advance_terminal.html
>
> 但 `editor-cli docs search` 的检索语料里**没有这一页**（实测 `docs search "Terminal"`、`"set_touch_handler"`、
> `"call_game"` 都命中不到它，只返回无关的月度更新公告），所以按关键词搜是搜不到的，只能直接访问上面的 URL。

## 1. 定位

- **游戏世界线**：角色、机关、分数、胜负与规则，由 `main.lua` 处理（默认开发入口）。
- **玩家操作台（Terminal）**：每位玩家一个，接触摸屏、鼠标、手柄等输入设备，并有一块观察世界线的显示器。
  入口脚本是 `main_terminal.lua`，负责读取当前玩家的输入、相机与设备信息，以及只影响当前玩家的本地表现。
- `main_terminal.lua` 中**只能使用 `TerminalAPI`**；其他游戏 API（如 `GameAPI`、`ActorAPI`）在该脚本中不可用。
- 官方定位为**实验特性**：当前仅开放部分输入、相机与设备能力，接口与使用方式可能调整。
- 门槛：需要同时写 `main_terminal.lua` 与 `main.lua` 并处理二者间的数据传递。若内置事件已够用，官方建议直接用内置事件。

## 2. 两条通信链路

| 方向 | API | 语义 |
| --- | --- | --- |
| 操作台 → 世界线 | `TerminalAPI.call_game(name, payload)` | 调用 `main.lua` 中的全局函数 `name`，参数是字符串 `payload` |
| 世界线 → 所有操作台 | `LuaAPI.call_terminal(name, args)` | 调用 `main_terminal.lua` 中的全局函数 `name`，参数是 table `args`（作为唯一参数传入，不会自动展开） |

- `payload` **必须是字符串**，复杂数据由作者用 `string.pack` / `string.unpack` 自行序列化。
- `args` 只能传简单表、字符串与数学类型，**不能传单位**。
- `call_game` 有限流：**任意连续 600 个显示更新周期内最多 60KB，超出部分直接丢弃**。官方建议按平均每个显示更新周期
  ≤100 字节设计，只在状态有效变化时提交。
- `call_terminal` 是可选链路，只有世界线需要主动要求各操作台做本地表现时才用。

```text
玩家输入 ──────────────────────────────┐
    ↓                                  │
玩家操作台（main_terminal.lua）        │
    │  TerminalAPI.call_game(...)      │
    ↓                                  │
游戏世界线（main.lua）                 │
    └─（可选）LuaAPI.call_terminal(...) ┘  向所有玩家的操作台注入操作信号
```

为什么必须走世界线：各操作台拿到的信息（触摸位置、相机方向、帧率、分辨率）可能不同，若各自直接改游戏世界会导致
「世界线分叉」。本地信息只用于本地反馈，正式结果由世界线产生。

## 3. 已公开的成员（官方「常用能力」表与案例）

### 输入

- `TerminalAPI.set_touch_handler(on_down, on_move, on_up)`
  三个回调依次是「按下 / 移动 / 抬起」，不需要处理的传 `nil`；回调签名 `(device_x, device_y, ui_x, ui_y)`。
- `TerminalAPI.get_touch_state` —— 读取当前按下/移动/抬起状态（返回结构官方未列出，见第 6 节）。
- `TerminalAPI.get_touch_position_device` / `TerminalAPI.get_touch_position_ui` —— 按两套坐标系取触摸位置。

### 坐标转换

- `TerminalAPI.convert_device_to_ui(device_x, device_y)` → UI 坐标
- `TerminalAPI.convert_ui_to_device(ui_x, ui_y)` → 设备坐标
- `TerminalAPI.device_to_world_origin(device_x, device_y)` → Vector3（世界射线起点，用于点选）
- `TerminalAPI.device_to_world_direction(device_x, device_y)` → Vector3（世界射线方向）
- `TerminalAPI.world_to_device` —— 3D 点投影到显示器

### 相机

- `TerminalAPI.get_main_camera()` → 相机对象；**场景加载期间可能返回 nil**，每次使用前重新获取并判空，不能长期缓存。
- `camera:get_direction()` → 相机朝向（案例二用它导出方向向量）。

### 设备与定时

- `TerminalAPI.get_fps()` —— 当前设备帧率
- `TerminalAPI.vibrate()` —— 震动
- `TerminalAPI.get_device_orientation()` —— 横竖屏
- `TerminalAPI.get_network_type()` —— 网络信息
- `TerminalAPI.set_tick_handler(callback, nil)` —— 显示更新回调，`callback(dt)`
- `TerminalAPI.create_timer` —— 定时器

注意（原文）：`set_tick_handler` / `set_touch_handler` **各自只能注册一个回调**，重复设置会覆盖，传 `nil` 清除。

## 4. 两套坐标系（原文表）

| | 设备坐标（device） | UI 坐标（ui） |
| --- | --- | --- |
| 原点 | 左上，y 向下 | 左下，y 向上 |
| 单位 | 真实像素 | 设计分辨率 |
| 用途 | `device_to_world_*` / `world_to_device` / `get_touch_position_device` | UI 布局对齐 / `get_touch_position_ui` |

转换用 `convert_device_to_ui` / `convert_ui_to_device`。两套比例随设备 DPI 变化，**不要硬编码**。

## 5. 最小骨架（摘自官方「快速入门」，原样可跑）

```lua
-- main_terminal.lua（玩家操作台）
TerminalAPI.set_touch_handler(
    function(device_x, device_y, ui_x, ui_y)
        local payload = string.pack("<ff", device_x, device_y)
        TerminalAPI.call_game("on_player_touch", payload)
    end,
    nil, -- 移动时不处理
    nil  -- 抬起时不处理
)
```

```lua
-- main.lua（游戏世界线）
function on_player_touch(payload)
    local device_x, device_y = string.unpack("<ff", payload)
    print("玩家按下屏幕：", device_x, device_y)
    -- 在这里处理角色、机关、分数等正式游戏逻辑
end
```

触摸点选（官方案例一的射线版）：

```lua
-- main_terminal.lua
local origin = TerminalAPI.device_to_world_origin(device_x, device_y)
local direction = TerminalAPI.device_to_world_direction(device_x, device_y)
TerminalAPI.call_game("on_touch_down", string.pack("<ffffff",
    origin.x, origin.y, origin.z, direction.x, direction.y, direction.z))
```

相机方向同步（官方案例二，含 nil 判空与变化阈值）：

```lua
-- main_terminal.lua
local last_direction = math.Vector3(0, 1, 0)
TerminalAPI.set_tick_handler(function(dt)
    local camera = TerminalAPI.get_main_camera()
    if camera == nil then return end
    local direction = camera.get_direction()
    if math.abs(direction:dot(last_direction)) < 0.999 then
        last_direction = direction
        TerminalAPI.call_game("on_camera_changed",
            string.pack("<fff", direction.x, direction.y, direction.z))
    end
end, nil)
```

## 6. 仍未公开、需实测

官方正文最后一行的说法是「完整 API 列表与签名见 TerminalAPI 文档」，但**该文档在手册站上不存在**：

- 手册的大而全 API 参考页 `/manual/pc_md/lua/EggyAPI.html`（5.2MB，GameAPI 签名 1555 处、LuaAPI 全签名）里
  `terminal` 大小写均是 **0 命中**，也没有 `call_terminal` 条目。
- 直接试 `TerminalAPI.html`、`terminal_api.html`、`lua_terminal_api.html`、`lua_api_terminal.html`、`terminal.html`、
  `lua_terminal.html` 全部 404。

因此以下签名仍未知：`get_touch_state` 的返回结构、`create_timer` 的参数与返回、`vibrate` 的参数、
`world_to_device` 的参数与返回、`get_network_type` 的取值枚举、`camera` 对象的其它方法。

另外两项待验证：

- 本机运行期实证：`party_pc\Documents\ea_log\log_2026.09.20_143506.ealog:238` 显示客户端 Lua 环境的 `_G` 里有
  `TerminalAPI:<TerminalAPI>`；但**帧同步地图的 `main.lua` 环境（探针可达）是否也有、能否直接调，尚未验证**。
- 本仓没有 `main_terminal.lua`（只有 `main.lua`）；部署目录因含重解析点无法遍历（PATH_RESTRICTED），main_terminal.lua 是否存在待确认。
  `editor-cli code init/diff/push` 是否把 `main_terminal.lua` 纳入同步集，也未验证。

之前那份结论仍然成立、与本节不矛盾：编辑器实时 meta（`api list`）只有 4 个 API（世界线/服务端侧），
仓根 `EggyAPI.lua` 由该 meta 生成，因此**两者都不会出现 TerminalAPI**。

## 7. 查证入口

```bash
# 官方章节（唯一有正文的地方，直接取 URL，docs search 索引不到）
#   https://u5-creator.s3.game.163.com/manual/pc_md/lua/lua_advance_terminal.html

# 大而全的 API 参考（含 GameAPI / LuaAPI 全签名，但没有 TerminalAPI）
#   https://u5-creator.s3.game.163.com/manual/pc_md/lua/EggyAPI.html

# 编辑器实时 meta（世界线侧，查不到客户端 API 属正常）
editor-cli api list --json
editor-cli api get TerminalAPI

# 运行期实证（需先开试玩）
lua tools/cli.lua probe <脚本> --timeout 10
```

## 8. 证据索引

| 事实 | 位置 |
| --- | --- |
| TerminalAPI 章节（实验特性、双脚本、call_game 限流、坐标系） | `manual/pc_md/lua/lua_advance_terminal.html` |
| 全站 API 参考无 TerminalAPI | `manual/pc_md/lua/EggyAPI.html`（`terminal` 0 命中） |
| docs search 索引不到该页 | `editor-cli docs search "Terminal" / "set_touch_handler"`（2026-11-19 实测） |
| FS 触摸注入链路 `terminal_api._on_screen_touch` | `%USERPROFILE%\.eggitor\cli\docs\input.md:41` |
| 运行期 `_G` 含 `TerminalAPI` / `LocalAPI` / `Modules` | `party_pc\Documents\ea_log\log_2026.09.20_143506.ealog:238` |
| `LocalAPI` 为空表 | 同上 `:258` |
| `UserInputService` 与触摸事件 | `party_pc\Documents\ea_log\log_2026.09.20_143602.ealog:698, :718, :728, :758` |
| `PhysicsService.raycast` 存在 | `party_pc\Documents\ea_log\log_2026.10.31_151216.ealog:950` |
| 编辑器 meta 无客户端 API | `editor-cli api list --json`（2026-11-19，editor-cli 0.20.17，mode=fs） |

## 9. 世界图（SE）对照：没有这套 API

世界编辑器（SE / 世界版）的文档树里查不到任何 Terminal 相关内容：

| 检查 | 结果 |
| --- | --- |
| SE 运行时 API 索引 `/manual/se/game_api/README.html`（419KB，全部 service / unit / 类入口） | `Terminal` **0** 命中；同一索引里 `UserInputService` / `PhysicsService` / `EUIButton` 各 1 条 |
| SE 手册 Lua 章节 `/manual/se/lua/07-players-input-character.html`（输入与角色） | `Terminal` 0 命中 |
| `editor-cli docs search --docset manual`（世界版手册）搜 `Terminal` / `TerminalAPI` | 0 条 |
| 文档树归属 | FS 那章挂在 `/manual/pc_md/…`（原点编辑器导航），SE 是独立的 `/manual/se/…` 导航 |

原因：SE 本身是 client / server 双端模型，客户端脚本能直接写 Lua 并与服务端通信（手册 03、07 章），
不需要再补一个「操作台」；FS（原点）没有客户端脚本，Terminal API 正是为这个缺口加的。

另注：`UserInputService` / `PhysicsService` / `EUIButton` 这些是 **SE 运行时 API**（`--docset game-api`）的条目，
在 FS 的 API 参考页 `/manual/pc_md/lua/EggyAPI.html` 里 0 命中——不要把它们当成 FS 的 Terminal API 成员。

留口：SE 若将来引入，会先出现在 `/manual/se/game_api/changelog/` 与 SE 的 `api list`（`lua/sdk/meta`）里。

