# 私有工作区（.local/）

`.local/` 用于跨会话保存任务状态和项目经验，不规定工作方法——怎么做由你自行判断。约定见 `.local/README.md`（首次操作 .local 前先读）。

- 跨会话的工作在 `.local/tasks/<slug>/` 建任务；接续时读任务 README 的「接续指引」，不凭记忆
- 在检查点刷新接续指引并在 .local 内 commit，保证会话随时中断，任何 agent 都能接手
- auto memory 已指向 `.local/memory/`，与其他 agent 共享，按标准结构写入
- 线上操作记到 `.local/ops/YYYY-MM.md`
- `.local/`、本文件、`.claude/settings.local.json`，以及 `.claude/`、`.agents/` 下 `local-` 前缀的私有扩展只在本机，永不进入主仓库或对外产物

**决策**：有客观正确答案的直接做；有多个合理选项的，选定后在任务 README 留痕，不阻塞；推翻用户已明确表达的方向时必须先问。
