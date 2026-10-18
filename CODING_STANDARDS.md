# Coding Standards

## 命名与 Lua

- 文件、模块、函数、变量使用 `snake_case`；类名使用 `CamelCase`。
- `src/` 的数字判断与转换使用 `src.foundation.number` 的 `NumberUtils`，不使用 `tonumber` 或 `type(value) == "number"`。
- Eggy `Fixed` 参数写浮点字面量，例如 `30.0`。
- Eggy 沙盒的上下界使用 `math.maxval` / `math.minval`。
- 源文件保持 UTF-8、LF；不把生成物或运行时状态写进源码目录。

## 分层与依赖

- 模块职责和放置规则见 [`docs/architecture.md`](docs/architecture.md)。依赖约束以 `tools/packages/arch_policy/policy.json` 与 `test/guards/` 的可执行规则为准（slim 的 guards 车道即层门禁）。
- `foundation` 是唯一 substrate，只含无玩法语义的通用能力，不依赖七层；`host` 是 L2 宿主适配层。
- `state` 与 `config` 不依赖上层；装配、mixin 安装和跨边界接线放在 `src/app`。
- 业务规则不接触 UI 节点或 Eggy API；宿主能力经 port 进入内层。
- `src/ui/manager` 是现有 host-EUI adapter 例外，不把该待遇扩散到其他 UI 模块。

## 宿主调用

- `EggyAPI.lua` / `EggyEditorAPI.lua` 是第三方注解线索，不是运行时事实；不得修改成项目实现。
- 宿主对象类名不稳定，业务逻辑不依赖 `type()` 返回的宿主类名。
- 已取证的宿主签名采用单次直调；`pcall` 只隔离宿主异常，成功按接口规定的明确信号判定（无返回值的调用回读状态翻转），不以“没有抛异常”为成功——宿主参数错误只记 ERROR 返回 nil，不抛异常。
- 宿主对象或方法缺失、调用异常与跳过路径必须留下可诊断日志，不静默吞掉。

## 测试

- 测试观察公共接缝和可见行为，不钉私有函数或内部调用次数；mock 只放在宿主、时间、随机数等系统边界。机械判据是 guards 车道 `test_lint_guard` 的 `call-count` 规则：计数变量在 stub/回调里自增（`n = n + 1`）、又被测试体的断言引用（`check.equal(N, n)`、`assert.is_true(n == 0)` 等）即判红。计数本身是公共契约（注入端口的出站次数、memo 重算次数、宿主边界的副作用等）时，在断言行或上一行写 `-- lint-allow: call-count <理由>` 豁免，理由必填。
- 测试体的每条执行路径至少经过一次断言；机械判据是 guards 车道 `test_lint_guard` 的 `vacuous-branch` 规则：含断言的 `if` 存在不经断言的穿越路径（无 `else` 而断言只在 then 分支、`if/else` 一侧无断言）即判红，即便同测试体别处有无条件断言——被条件挡住的断言本身即是空转检查。确属合理的条件断言（按数据子集扫描、平台分支等），在判红行或上一行写 `-- lint-allow: vacuous-branch <理由>` 豁免，理由必填。
- 改 `src/rules/**` 前先补或调整 behavior spec；行为回归放 `test/behavior/`。
- 期望值来自规格、字面例子或独立真源，不用与实现相同的算法重算期望值。

## 断言层与运行后端(#74 / #90,ADR 0069)

迁移顺序是**先断言、后结构**:先把 `lu.*` / `luax.has_error` 换成真 luassert,`TestX = {}` 类结构原样留着;结构层(`describe` / `it`)换 busted 时再做第二步。两步之间的中间态允许进仓库,**不建「TestX 自动包成 describe」或「lu.* 转发到 luassert」的兼容层**——shim 出错的表现是测试静默通过。

#90 之后旧后端已物理退场:自研 `luaunit_runner`(runner / registry / file_isolation / events / outputter / chunk_cache)、`packages.test_runner` 的双后端分派(`backend_manifest` / `manifest` / `events` / `update_manifest`)与 `test/support/luax.lua` 全部删除。唯一执行后端是真实 busted,入口 `tools/packages/test_runner/runner.lua`。

### 断言对象怎么拿

- 仍走旧 Test 风格的 spec 文件头两行固定:`require("test.bootstrap").install_package_paths()` 之后 `local luassert = assert(require("test.support.luassert_loader").load())`,断言只走这个局部对象。该 loader 仍服务于场景套件、`shared_support`、`property`、`fuzz` 等尚未切 DSL 的支撑模块。
- loader 只从**受控 Lua 环境**（`luarocks config rocks_trees` 解析出的机器 LuaRocks tree，见 GLOSSARY）装载 `luassert`、其子模块及 `say`。未验证的 `package.loaded` 预注入即失败;装载期间的优先 searcher 按受控 tree 内的文件显式 loadfile,避免 preload/searcher 绕过;后续调用复核已加载对象身份。解析路径在受控 tree 中不代表预加载对象来自 tree。真实 busted 侧由 `packages.test_runner.cache_loader` 施加同一口径的真身校验。本仓不安装、不写入任何 rocks tree。
- **不覆盖全局 `assert`**。后端语义若挂在全局 `assert` 上,覆盖它等于换执行后端而不是换断言词汇。

- #75 显式登记为 busted 的真实 `describe` / `it` 文件使用 busted 注入的断言对象（可写 `local luassert = assert`）；运行器先验证并从受控 Lua 环境装载真实 busted/luassert 依赖。不得将旧 Test 表动态包成 DSL，不得在 spec 中替换全局断言对象。普通 require 保持跨文件模块身份，singleton patch 由 spec 在 teardown 中显式恢复。

### 译法对照(带陷阱)

| 迁移前 | 迁移后 | 陷阱 |
| --- | --- | --- |
| 标量 `lu.assertEquals(a, b)` | `luassert.is.equal(b, a)` | **参数顺序翻转**成 (expected, actual);`is.equal` 是 `==`,表只比身份 |
| 表 `lu.assertEquals(a, b)` | `luassert.is.same(b, a)` | LuaUnit 原本深比较表;luassert 的 `is.same` 忽略元表做深比较,不可换成身份比较 |
| `lu.assertNotEquals(a, b)` | 标量用 `luassert.is_not(b, a)`,表用 `luassert.is_not.same(b, a)` | 必须保住标量不等或表内容不等的原口径 |
| `lu.assertIs` / `lu.assertNotIs` | `luassert.is.equal` / `is_not`(同一引用) | 比的是引用,不是内容 |
| `lu.assertEvalToTrue(x)` | `luassert.truthy(x)` | **truthiness**,`1` / `"s"` / 表都通过 |
| `lu.assertEvalToFalse(x)` | `luassert.falsy(x)` | 只认 `nil` 与 `false` |
| `lu.assertTrue(x)` / `lu.assertFalse(x)` | `luassert.is_true(x)` / `is_false(x)` | **严格布尔**,`is_true(1)` 必红;别拿 `truthy` 顶替 |
| `lu.assertNil` / `lu.assertNotNil` | `luassert.is_nil` / `is_not_nil` | `is_nil(false)` 必红,`false` 不是 `nil` |
| `lu.assertIsTable` 等类型断言 | `luassert.is_table` 等 | `is_*` 家族即类型断言 |
| `lu.assertError(f, ...)` | `luassert.has_error(function() f(...) end)` | `lu.assertError` 把尾参**传给 f**、只验「抛没抛」;`has_error` **不转发参数**,给了 expected 就**精确比文本**。保住原义要显式包闭包、不顺手把期望值升级成精确文本——那是改期望值 |
| `lu.assertErrorMsgContains(sub, f, ...)` | `luassert.has_error.match(function() f(...) end, sub, 1, true)` | 旧断言转发尾参;新断言需闭包保住调用。`has_error` 是**精确文本**,子串必须走 `match` 且加 `1, true`(init + plain,禁用模式元字符) |
| `luax.has_error(f, msg)` | `luassert.has_error(f, msg)` | 同口径(先剥一层 `文件:行: ` 位置前缀,字符串精确比、表深比),换名即可 |
| `lu.assertStrContains(s, sub)` | `luassert.matches(sub, s, 1, true)` | 同上,plain 模式 |

### 失败如何传播

真实 busted 只有 `passed` / `failed` / `errors` 三桶,统一由一个退出码收口:`exit = (failed + errors > 0 or cases == 0) and 1 or 0`。

- luassert 的断言失败走 busted 的 `failure` 事件,计 **failed**;
- 测试体或钩子里未捕获的运行时抛错、加载失败、空 spec 文件、拆了共享端口基线未装回(见 `test/helper.lua` 的 `# BASELINE LEAK`)计 **errors**。

三个桶都**独立**作用于退出码:只 failed、只 errors、或 cases == 0,退出码都是非零。改动断言层后如果 `errors` 归零而 `failed` 也归零,先怀疑断言被吞了,而不是修好了。

### 诊断

Lua 编译期 `LUA_IDSIZE` 是 60,长 chunk 名在错误消息里被截成 `...<尾部>`,所以 TAP 的 `# <src> @ <line>` **不保证是完整路径**——对账与归因按文件名(basename),不要拿它当绝对路径去拼。

## 旧 mutate4lua manifest（已退役）

- mutate4lua 与 `lua tools/cli.lua mutate` 已于 #94 退役；变异测试改走显式步骤 `lua tools/cli.lua uml mutate`（契约见 `tools/specs/uml_quality.prompt`）。
- `src` 文件尾部残留的 `--[[ mutate4lua-manifest` 块注释是惰性历史产物：不再被任何工具读取，新文件不要添加，改动函数时也无需更新。
- survived、timeout 或仅差分通过都不能证明全量基线。
