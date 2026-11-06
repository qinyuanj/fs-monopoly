# Coding Standards

## 命名与 Lua

- 文件、模块、函数、变量使用 `snake_case`；类名使用 `CamelCase`。
- `src/` 的数字判断与转换使用 `src.foundation.number` 的 `NumberUtils`，不使用 `tonumber` 或 `type(value) == "number"`（`tonumber` 由 guards 车道 `forbidden_globals` 拦截）。
- Eggy `Fixed` 参数写浮点字面量，例如 `30.0`。
- Eggy 沙盒的上下界使用 `math.maxval` / `math.minval`。
- 源文件保持 UTF-8、LF；生成物和运行时状态不进源码目录。

## 分层与依赖

- 模块职责和放置规则见 [`docs/architecture.md`](docs/architecture.md)。层序与同层分组的唯一真源是 `tools/packages/arch_policy/levels.edn`；其余边界规则以 `tools/packages/arch_policy/policy.json` 与 `test/guards/` 为准（slim 的 guards 车道即层门禁）。
- 业务规则不接触 UI 节点或 Eggy API；宿主能力经 port 进入内层。

## 宿主调用

- `EggyAPI.lua` / `EggyEditorAPI.lua` 是第三方注解线索，不是运行时事实，不得改成项目实现。
- 宿主对象类名不稳定，业务逻辑不依赖 `type()` 返回的宿主类名。
- 已取证的宿主签名采用单次直调。`pcall` 只隔离宿主异常，成功按接口规定的明确信号判定，无返回值的调用回读状态翻转；宿主参数错误只记 ERROR 并返回 nil，所以“没抛异常”不算成功。取不到成功信号的调用是登记例外（`end_game`、换模型），见 [`docs/decisions.md`](docs/decisions.md) ADR 0046。
- 宿主对象或方法缺失、调用异常与跳过路径必须留下可诊断日志。

## 重复检测（dry）

- 抽函数前跑 `lua5.4 tools/cli.lua dry <文件或目录>`；阈值低于约 0.7 时噪声会淹没真信号。
- `host_types` 的 vec3 / quat 类数据类重复是有意不治理的，忽略这里的命中。

## 测试

通用测试原则见全局 `tdd` skill，本节只写本仓特有的约定。

- 随机数替身只断言结果，不断言抽了几次：帧同步下的抽取次数不是契约。
- 改 `src/rules/**` 前先补或调整 behavior spec；行为回归放 `test/behavior/`。
- 变异测试报存活的等价变异体（怎么写测试都杀不死）时，先删造成它的冗余代码，如恒真守卫、不可达分支、被短路的死默认值。删不掉就在源码注释说明原因，不为它补测试。

### 机械判据

guards 车道 `test_lint_guard` 执行以下规则：

- `call-count`（不钉内部调用次数）：计数变量在 stub/回调里自增（`n = n + 1`），又被测试体的断言引用（`check.equal(N, n)`、`assert.is_true(n == 0)` 等）。计数本身是公共契约（注入端口的出站次数、memo 重算次数、宿主边界的副作用等）时可豁免。
- `vacuous-branch`（每条执行路径至少经过一次断言）：含断言的 `if` 存在不经断言的穿越路径（无 `else` 而断言只在 then 分支、`if/else` 一侧无断言），即便同测试体别处有无条件断言。合理的条件断言（按数据子集扫描、平台分支等）可豁免。
- `indexed-case-table`（用例体直接写在 `it` 里）：spec 里值全是函数字面量的 `local` 表。这样的用例体会躲开上面两条规则，漏注册的条目也不会被跑到。

豁免写在判红行或上一行：`-- lint-allow: <规则> <理由>`，理由必填。

## 断言层与运行后端（#74 / #90，ADR 0069）

唯一执行后端是真实 busted，入口 `tools/packages/test_runner/runner.lua`。断言使用真实 luassert，测试结构使用 `describe` / `it`。不得建立包装旧 Test 表或转发旧断言词汇的兼容层：shim 出错的表现是测试静默通过。

### 断言对象怎么拿

- spec 文件使用 busted 注入的断言对象（可写 `local luassert = assert`）。
- 场景套件、`shared_support`、`property`、`fuzz` 等支撑模块在 `require("test.bootstrap").install_package_paths()` 之后使用 `local luassert = assert(require("test.support.luassert_loader").load())`，断言只走这个局部对象。
- **不覆盖全局 `assert`**，spec 也不替换全局断言对象。后端语义挂在全局 `assert` 上，覆盖它等于换执行后端。
- `luassert`、其子模块及 `say` 只从**受控 Lua 环境**装载（ADR 0072）。
- 普通 require 保持跨文件模块身份，singleton patch 由 spec 在 teardown 中显式恢复。

### 失败如何传播

断言失败计 **failed**；未捕获的运行时抛错、加载失败、空 spec 文件、拆了共享端口基线未装回（见 `test/helper.lua` 的 `# BASELINE LEAK`）计 **errors**。两者任一非零或 cases == 0，退出码都非零。改动断言层后如果 `errors` 与 `failed` 同时归零，先怀疑断言被吞了，而不是修好了。

### 诊断

Lua 编译期 `LUA_IDSIZE` 是 60，长 chunk 名在错误消息里被截成 `...<尾部>`，所以 TAP 的 `# <src> @ <line>` **不保证是完整路径**：对账与归因按文件名（basename），不要拿它拼绝对路径。
