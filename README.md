# marginalia

项目私有工作区 `.local/`：跨会话保存任务状态、项目经验和 ops 记录，不规定工作方法；兼容多种 agent 工具（Claude Code、Codex、Gemini CLI 等）。

## 组成

| 路径 | 作用 |
|---|---|
| `bin/marginalia` | 确定性操作：`setup` / `init` / `task`，任何 agent 或人都可调用 |
| `skills/` | Agent Skills 标准格式：`marginalia-init`、`marginalia-task`、`marginalia-kickoff` |
| `templates/local/` | `.local/` 内的初始文件（规范 README、任务模板等） |
| `templates/claude-local-block.md` | 写入项目 `CLAUDE.local.md` 的托管块 |
| `templates/agent-global-block.md` | 写入 Codex / Gemini 全局指令文件的托管块 |

## 安装

```sh
~/workspace/_smoke/marginalia/bin/marginalia setup
```

- skills 软链到 `~/.agents/skills/`（Codex、Gemini CLI）和 `~/.claude/skills/`（Claude Code）
- `marginalia` 软链到 `~/.local/bin/marginalia`
- `~/.codex/AGENTS.md`、`~/.gemini/GEMINI.md` 写入入口托管块（对应工具未安装时跳过，装好后重跑）

## 项目内的结构

`marginalia init` 只写这些位置，不改主仓库里受版本控制的文件：

- `.local/`：独立 git 仓库；worktree 中是指向主工作区 `.local` 的软链
- `.git/info/exclude`：排除 `.local`、`CLAUDE.local.md`、`.claude/settings.local.json` 和 `local-` 前缀的私有扩展
- `CLAUDE.local.md`：Claude 的入口托管块；项目没有 `CLAUDE.md` 时块内带 `@AGENTS.md`（否则 Claude 会因为有 CLAUDE.local.md 而不读 AGENTS.md）
- `.claude/settings.local.json`：`autoMemoryDirectory` 指向 `.local/memory`（必须是绝对路径），让 Claude 的 auto memory 成为各 agent 共享的经验库

推荐的项目指令结构：`AGENTS.md` 放共享内容，`CLAUDE.md` 写 `@AGENTS.md`，`CLAUDE.local.md` 只放私有内容。

## 各工具实测情况（2026-10-13）

| 工具 | 入口 | skill 发现 | 接续任务 | 写 .local |
|---|---|---|---|---|
| Claude Code 2.1.296 | `CLAUDE.local.md` 托管块 | ✅ `~/.claude/skills` | ✅ | ✅ 建任务、commit；auto memory 写入 `.local/memory` |
| Codex 0.162.1 | `~/.codex/AGENTS.md` 托管块 | ✅ `~/.agents/skills` | ✅ | ✅ workspace-write 沙箱下能 commit `.local`（只有主仓库 `.git` 是只读的）；经验按同一结构写入 |
| Gemini CLI 0.63.0 | `~/.gemini/GEMINI.md` 托管块 | ✅ `~/.agents/skills` | ⚠️ 能完成 | ⚠️ 未测写入 |

已知限制：Gemini 的 `read_file` 会拒绝读取被 git 忽略的路径（`.local/` 被 exclude 排除），需要绕道才能读到。`respectGitIgnore` 是项目级的全局开关，关掉会把 `node_modules` 等也暴露出来，所以暂不处理。
