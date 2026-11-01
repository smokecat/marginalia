# Changelog

格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 变更

- 私有工作区默认目录名由 `.local` 改为 `.margin`；模板、托管块、skill 和全局入口里的目录名按实际配置生成。
- 任务库身份（`store.id`）改为存进工作区自己的 git config，改目录名后不变；旧项目首次 `init` 时按原路径写入，已有的 trine 会话关联不受影响。
- 不在 git 项目中或项目没有工作区时，task 命令的退出码由 1 改为 5；trine 扩展据此判断，不再匹配错误文字。
- README 推荐的安装位置由 `~/.marginalia` 改为 `~/.local/share/marginalia`（`~/.marginalia` 现在放用户配置）。

### 新增

- 目录名分级配置：系统 `/etc/marginalia/config` < 用户 `~/.marginalia/config` < 环境变量 `MARGINALIA_DIR` < 项目（`.git/config` 的 `marginalia.dir`）；`marginalia config` 查看和设置。
- `marginalia init --dir <名字>`：为项目指定目录名；`init` 会把实际用的目录名写进项目配置，之后改默认值不影响已有项目。
- `marginalia migrate [--to 名字] [--dry-run]`：给已有工作区改名（包括把旧版 `.local` 迁到 `.margin`），同步 worktree 软链、exclude、托管块、auto memory 设置和 `.claude/`、`.agents/` 下指进工作区的软链，可重跑、可迁回；列出正文里还提到旧目录名的文件。
- 旧版 `.local` 项目不迁移也能照常使用。
- `task list --json` / `task show --json` 的 `store` 增加 `dir`、`project`。

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
