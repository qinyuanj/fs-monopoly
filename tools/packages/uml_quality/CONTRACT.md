# uml 子命令补充契约

CLI 形态与退出码以 `lua5.4 tools/cli.lua uml --help` 为准；为何钉环境、为何不用仓根 `./uml`、`.metrics/` 入库、变异范围见 `docs/decisions.md` ADR 0068 / 0070 / 0072 / 0076。本文只记录 `--help` 与 ADR 都不承载、不写下来就会被误改的约束。

## 环境搭建（手动，本仓只核对不安装）

- uml-viewer、crapper、mutator 由上游 `get-uml-viewer` 装到邻接 `.uml-viewer/`；`UML_VIEWER_TOOL_ROOT` 可指向开发检出。这些仓对本项目只读。
- 每个检出一个 Python 3.11+ venv：`python3 -m venv .uml-viewer/crapper/.venv`，再 `.uml-viewer/crapper/.venv/bin/python -m pip install -e .uml-viewer/crapper`；mutator 同理，另加 `-e .uml-viewer/crapper`。
- 预检要求各 venv 的包从自身检出（`.uml-viewer/<tool>/src`）导入，mutator 的 `ensure_crapper()` 解析到 `.uml-viewer/crapper/src`；全局装的同名包不能造成假绿。

## `uml-quality.json` 的硬约束

- 只声明 `standardTools`，`sourceRoots: ["src"]`。
- `exclude: []` 必须显式保留：上游 mutation scope 适配器把缺省的 `exclude` 包成 `@($null)` 而失败。变异排除 UI 不能写进这里（ADR 0076 第 2 条）。
- `crapperOptions` / `mutatorOptions` 不写路由类参数（`--root`、`--source-root`、`--exclude`、`--full-tree`、`--changed`、`--mutate-all`），上游会拒绝；crap 由包装器固定 `--full-tree`。
- 预检经上游 `probe_config.py` 用其自身的 `read_config` / `scope` / `targets` 校验本文件，不在本仓重写校验逻辑。

## `ir` 的上游陷阱

- 仓根若存在 `examples/`，上游 `ir` 会优先读 `examples/*.policy.edn` 而忽略生成的 `policy.edn`；预检因此拒绝仓根 `examples/`。
- 上游 `ir` 按位置取 `[policy [output]]`，包装器必须两个都传；只传一个时输出会落到 `examples/uml-viewer.edn`。

## 验证范围

- 默认 tooling 车道只跑 Lua CLI 测试。改动 mutate 证据核验时，另在装好的环境里先过 `lua5.4 tools/cli.lua uml check`，再跑 `.uml-viewer/mutator/.venv/bin/python -I -B -m unittest discover -s tools/packages/uml_quality/test -p test_mutation_evidence.py`。环境缺失即「未执行」，不算通过或跳过。
- `uml view` 的图窗、companion、CRAP 着色与 Herdr 清理由维护者在 WSL Ubuntu / macOS 上人工验证，不在自动化测试内。
