# Triage Labels

工程技能以五个规范 triage 角色说话。本文件把角色映射到本仓工单系统（GitHub）实际使用的标签字符串。

| mattpocock/skills 角色 | 本仓标签 | 含义 |
| ---------------------- | -------- | ---- |
| `needs-triage` | `needs-triage` | 维护者需要评估该工单 |
| `needs-info` | `needs-info` | 等报告者补充信息 |
| `ready-for-agent` | `ready-for-agent` | 已完整规约，可交给 AFK agent |
| `ready-for-human` | `ready-for-human` | 需要人工实现 |
| `wontfix` | `wontfix` | 不予处理 |

技能提到角色时（如「打上 AFK-ready 标签」），用上表右侧的标签字符串。用标签前先 `gh label list --repo qinyuanj/fs-monopoly --json name` 核对实例里已存在的名称。
