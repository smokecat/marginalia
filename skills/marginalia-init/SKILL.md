---
name: marginalia-init
description: 在当前项目初始化、修复或升级 .local 私有工作区（跨会话任务持久化、各 agent 共享的经验库、ops 记录），只在用户明确要求时使用。幂等，可重复运行。
license: MIT
---

# marginalia-init

运行 `marginalia init [目录]`（不在 PATH 时用 `~/.local/bin/marginalia`），按输出标签处理：

- `[ASK]`：需要用户决定。逐项向用户说明并询问，同意的项加上对应选项重跑 `marginalia init`：
  - `--git-init`：目录不是 git 仓库（先确认用户确实要在这个目录初始化）
  - `--update-spec`：规范模板有更新。先用输出里给的 diff 命令概述差异，再问
  - `--create-claude-md`：项目只有 AGENTS.md，建议建一个共享的 CLAUDE.md（内容为 `@AGENTS.md`），需要提交到主仓库。团队仓库要提醒用户这一点
  - `--migrate-memory`：把 Claude 原有的 auto memory 复制进 .local/memory/
- `[CONFLICT]` / `[WARN]`：原样转告用户并给出处理建议，不要擅自改主仓库里的文件
- 其余标签（CREATED / UPDATED / SKIPPED / FIXED / COMMITTED）汇总成简短报告

脚本只写 `.local/`、`.git/info/exclude`、`CLAUDE.local.md`、`.claude/settings.local.json`，主仓库里受版本控制的文件只在 `--create-claude-md` 时才会新增。
