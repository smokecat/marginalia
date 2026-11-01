---
name: marginalia-init
description: 在当前项目初始化、修复、升级或改名 marginalia 私有工作区（默认 .margin/；跨会话任务持久化、各 agent 共享的经验库、ops 记录），也负责把旧版 .local/ 迁到新目录名。只在用户明确要求时使用。幂等，可重复运行。
license: MIT
---

# marginalia-init

运行 `marginalia init [目录]`（不在 PATH 时用 `~/.local/bin/marginalia`），按输出标签处理。用户指定了目录名时加 `--dir <名字>`；默认目录名由 `marginalia config` 决定（`marginalia config --list` 查看各级设置）。

- `[ASK]`：需要用户决定。逐项向用户说明并询问，同意的项加上对应选项重跑 `marginalia init`：
  - `--git-init`：目录不是 git 仓库（先确认用户确实要在这个目录初始化）
  - `--update-spec`：规范模板有更新。先用输出里给的 diff 命令概述差异，再问
  - `--create-claude-md`：项目只有 AGENTS.md，建议建一个共享的 CLAUDE.md（内容为 `@AGENTS.md`），需要提交到主仓库。团队仓库要提醒用户这一点
  - `--migrate-memory`：把 Claude 原有的 auto memory 复制进工作区的 memory/
  - 提示 `marginalia migrate`：项目还在用旧目录名（如 `.local/`），或用户要给已有工作区改名。先跑 `marginalia migrate --dry-run [--to 名字]` 把计划告诉用户，同意后再去掉 `--dry-run` 执行；提醒用户迁移后重启本项目里正在运行的 agent 会话。输出里列出的「正文提到旧目录名」的文件，按用户意愿逐个修改
- `[CONFLICT]` / `[WARN]`：原样转告用户并给出处理建议，不要擅自改主仓库里的文件
- 其余标签（CREATED / UPDATED / SKIPPED / FIXED / COMMITTED）汇总成简短报告

脚本只写私有工作区、`.git/info/exclude`、`.git/config` 的 `marginalia.dir`、`CLAUDE.local.md`、`.claude/settings.local.json`，主仓库里受版本控制的文件只在 `--create-claude-md` 时才会新增。
