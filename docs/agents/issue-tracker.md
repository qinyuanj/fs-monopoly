# Issue Tracker（GitHub / gh）

工单住 GitHub：`https://github.com/qinyuanj/fs-monopoly`。读写一律走已认证的 `gh` CLI，不用裸 curl；CLI 未覆盖端点时才用 `gh api`。台账 / 待办 / 悬而未决事项一律开工单，不进仓库。工单号在提交信息里以 `#<idx>` 引用。显式传 `--repo qinyuanj/fs-monopoly`，不受当前目录 remote 影响。

## 执行流程

1. **读取现状**

   ```bash
   gh issue view <idx> --repo qinyuanj/fs-monopoly --comments --json number,title,body,comments,labels,state,assignees,url
   ```

   完成标准：取得标题、状态、正文、标签和全部评论；需要编辑或删除评论时，同时取得评论数据库 ID。

   长正文工单整体 dump 会被输出截断（含后台任务日志）；只提取所需字段：

   ```bash
   gh issue view <idx> --repo qinyuanj/fs-monopoly --json body --jq .body
   ```

2. **执行最小变更**
   - 只传需要变更的字段。
   - 修改正文前保留现有全文；`--body-file` 会整体替换正文。
   - 多行 Markdown 使用 UTF-8 临时文件配合 `--body-file`。
   - 使用标签前以 `gh label list --repo qinyuanj/fs-monopoly --json name,color,description` 核对名称。

3. **回读核验**

   ```bash
   gh issue view <idx> --repo qinyuanj/fs-monopoly --comments --json number,title,body,comments,labels,state,assignees,url
   ```

   完成标准：目标字段、状态和评论与请求一致；删除的评论数据库 ID 已不存在；Markdown 结构完整。

## 常用操作

```bash
gh issue list --repo qinyuanj/fs-monopoly --state all --search 关键词 --json number,title,state,labels,url
gh issue create --repo qinyuanj/fs-monopoly --title "标题" --body-file <path> --label 标签1 --label 标签2
gh issue edit <idx> --repo qinyuanj/fs-monopoly --title "新标题" --body-file <path>
gh issue edit <idx> --repo qinyuanj/fs-monopoly --add-label 追加标签 --remove-label 去除标签
gh issue close <idx> --repo qinyuanj/fs-monopoly --reason completed
gh issue reopen <idx> --repo qinyuanj/fs-monopoly

gh issue comment <idx> --repo qinyuanj/fs-monopoly --body-file <path>
gh api repos/qinyuanj/fs-monopoly/issues/<idx>/comments --jq '.[] | {id, body}'
gh api -X PATCH repos/qinyuanj/fs-monopoly/issues/comments/<comment_id> -f body="新正文"
gh api -X DELETE repos/qinyuanj/fs-monopoly/issues/comments/<comment_id>

gh label list --repo qinyuanj/fs-monopoly --json name,color,description
```

`create` 返回新工单 URL；从 URL 末段取得 `<idx>`，随后按执行流程回读核验。

## 多行正文

```bash
gh issue create --repo qinyuanj/fs-monopoly --title "标题" --body-file <path>
gh issue edit <idx> --repo qinyuanj/fs-monopoly --body-file <path>
gh issue comment <idx> --repo qinyuanj/fs-monopoly --body-file <path>
```

`--body-file` 统一接收 UTF-8 文件；`
` 和字面字符按文件内容原样保存。`--body` 也可直接传正文，但多行和特殊字符使用文件更稳定。

## 约定与坑

- `gh issue view <idx>` 缺省不含评论；读取完整上下文显式传 `--comments`。
- 评论编辑和删除使用评论数据库 ID，不使用工单号；先用 API 从工单评论中取得 `id`。
- `gh issue edit --add-label` 追加标签；删除标签使用 `--remove-label`。
- 机器读取使用 JSON，不解析终端表格。
- 指派可直接用 `gh issue edit <idx> --repo qinyuanj/fs-monopoly --add-assignee <user>`。
- 列表默认有限制；完整枚举时设置足够大的 `--limit` 或使用 `gh api --paginate`。
- 仓库解析失败时优先核对 `gh auth status`，仍显式传 `--repo qinyuanj/fs-monopoly`。

## PR 不作为请求入口

本仓 triage 队列只看 issue；GitHub Pull Request 不进 triage 视野。

## 真源

- 工单登记和读写规则以本文为准；任务入口与其余知识路由见仓库根部 `AGENTS.md`。
