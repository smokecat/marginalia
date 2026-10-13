---
name: marginalia-task
description: 管理项目 .local 私有工作区中的持久化任务（新建、接续、列表、改状态、归档）。仅在项目根存在 .local/ 时适用。触发场景：开始一项明显会跨会话的工作；用户说"继续/接续 xx"，或提到之前没做完的工作；用户显式要求列出、归档任务或修改任务状态。
---

# marginalia-task

规范在项目的 `.local/README.md`，首次操作前先读。机械操作用 `marginalia` 命令（不在 PATH 时用 `~/.local/bin/marginalia`），它会顺带完成 .local 内的 commit：

| 操作 | 命令 | 你还要做的 |
|---|---|---|
| 新建 | `marginalia task new <slug> [标题]` | 先跑 `marginalia task list` 查重。建好后结合用户描述和当前会话，填写目标、范围、待办、接续指引，然后 commit |
| 接续 | `marginalia task list` 定位任务 | 读任务 README（重点是接续指引）和需要的文件，用两三句话复述状态和下一步，然后直接开始干 |
| 列表 | `marginalia task list` | — |
| 改状态 | `marginalia task status <slug> <active\|paused\|blocked\|done>` | — |
| 归档 | `marginalia task archive <slug> [一句话结果]` | 状态不是 done 时先向用户确认，再加 `--force` |

项目没有 .local/ 时不适用；用户想启用就用 marginalia-init。
