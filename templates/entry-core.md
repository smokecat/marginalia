# 私有工作区（{{DIR}}/）

`{{DIR}}/` 用于跨会话保存任务状态和项目经验，不规定工作方法——怎么做由你自行判断。约定见 `{{DIR}}/README.md`（首次操作 {{DIR}} 前先读）。

- 跨会话的工作在 `{{DIR}}/tasks/<slug>/` 建任务；接续时读任务 README 的「接续指引」，不凭记忆
- 在检查点刷新接续指引并在 {{DIR}} 内 commit，保证会话随时中断，任何 agent 都能接手
- 项目经验库 `{{DIR}}/memory/` 各 agent 共享：开工前读 `MEMORY.md` 索引，按需读条目，写入按 README 的结构
- 线上操作记到 `{{DIR}}/ops/YYYY-MM.md`
- `{{DIR}}/`、各 agent 的本地私有文件（如 `CLAUDE.local.md`、`.claude/settings.local.json`），以及 `.claude/`、`.agents/` 下 `local-` 前缀的私有扩展只在本机，永不进入主仓库或对外产物

**决策**：有客观正确答案的直接做；有多个合理选项的，选定后在任务 README 留痕，不阻塞；推翻用户已明确表达的方向时必须先问。
