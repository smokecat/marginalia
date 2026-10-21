# Changelog

格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增

- `marginalia setup` / `uninstall`：安装或撤销 skills 软链、命令和各 agent 的全局入口（Codex、Gemini CLI）。
- `marginalia init`：在项目落地 `.local/` 私有工作区，幂等，兼作修复和升级；支持 `--git-init`、`--update-spec`、`--create-claude-md`、`--migrate-memory`。
- `marginalia task new | list | status | archive`：任务操作，并自动在 `.local` 内 commit。
- 符合 Agent Skills 标准的三个 skill：`marginalia-init`、`marginalia-task`、`marginalia-kickoff`。
- Claude Code auto memory 指向 `.local/memory/`，作为各 agent 共享的经验库。
- 项目没有 `CLAUDE.md` 时在 `CLAUDE.local.md` 托管块内 `@AGENTS.md` 兜底。
- worktree 自动共享主工作区的 `.local`。
- bats 测试套件与 `scripts/check`，CI 覆盖 Linux 和 macOS（bash 3.2）。
- `marginalia task list --json [--archived]`、`marginalia task show <slug> --json`：机器可读的任务列表与详情（含接续指引、任务库身份）。
- trine 扩展（`integrations/trine/`）：在 trine 的会话页查看任务、关联会话、一键接续；新建会话时「从任务开始」（需要 trine agent 0.17.0）。

### 修复

- `task status` / `task archive` 没有校验 slug，`../x` 这样的参数能操作 `tasks/` 之外的文件。
- 写任务的命令会把用户另外暂存在 `.local` 里的改动一起提交；现在只提交本次操作的路径，commit 失败时退出码为 4。
- 重复归档已归档的任务不再报错。
