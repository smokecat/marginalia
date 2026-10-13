# marginalia

[![CI](https://github.com/smokecat/marginalia/actions/workflows/ci.yml/badge.svg)](https://github.com/smokecat/marginalia/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**给 coding agent 的零痕迹私有工作区。** 在项目里放一个只有你本机可见的 `.local/`，让 Claude Code、Codex、Gemini CLI 等工具跨会话、跨工具地接续任务、共享项目经验——不往共享仓库里提交任何文件。

> *marginalia*：页边批注。在别人的书页边上写自己的笔记，书本身不变。

## 为什么

- **会话会断，上下文会丢。** 跨几天的工作需要一份"下一个会话读了就能接着干"的交接记录。
- **你会换工具。** 今天用 Claude、明天用 Codex，任务状态和踩过的坑应该放在同一个地方，而不是锁在某个工具的私有存储里。
- **仓库不一定是你的。** 在团队仓库里，你未必想（或被允许）提交 agent 相关的配置文件。marginalia 只写 git 不跟踪的文件，`git status` 始终干净。

marginalia **不规定工作方法**。它只负责把状态持久化、把入口接到各个工具上；怎么干活由 agent 自己判断。

## 工作原理

```
your-project/
├── .local/                     # 独立 git 仓库，经 .git/info/exclude 排除
│   ├── README.md               # 约定说明，各 agent 首次操作前读它
│   ├── tasks/<slug>/README.md  # 跨会话任务；核心是「接续指引」
│   ├── tasks/archived/
│   ├── memory/MEMORY.md        # 各 agent 共享的项目经验库
│   ├── ops/YYYY-MM.md          # 线上操作记录
│   ├── todo.md
│   └── docs/ scripts/ templates/ out/ logs/ tmp/
├── CLAUDE.local.md             # Claude 的入口（托管块）
└── .claude/settings.local.json # autoMemoryDirectory → .local/memory
```

| 工具 | 入口 | skills |
|---|---|---|
| Claude Code | 项目内 `CLAUDE.local.md` 托管块 | `~/.claude/skills/` |
| Codex | `~/.codex/AGENTS.md` 托管块（遵守 `CODEX_HOME`） | `~/.agents/skills/` |
| Gemini CLI | `~/.gemini/GEMINI.md` 托管块 | `~/.agents/skills/` |

几个关键设计：

- **零痕迹**：只写 `.git/info/exclude`、`CLAUDE.local.md`、`.claude/settings.local.json` 和 `.local/`，不修改主仓库中任何受版本控制的文件。
- **共享经验库**：把 Claude Code 的 auto memory 目录指向 `.local/memory/`，Claude 照常自动维护，其他 agent 按同一结构读写，不会重复占用上下文。
- **不挡住 AGENTS.md**：项目里只要有 `CLAUDE.local.md`，Claude Code 默认就不再读 `AGENTS.md`。项目没有 `CLAUDE.md` 时，托管块里会带 `@AGENTS.md` 兜底。
- **worktree 共享**：worktree 里的 `.local` 是指向主工作区的软链，和 Claude auto memory 跨 worktree 共享的行为一致。
- **任务状态只存一处**：任务 README 的 frontmatter 就是状态，没有另外的索引文件需要同步。

## 安装

依赖：bash ≥ 3.2、git ≥ 2.31、python3 ≥ 3.8（只用标准库）。支持 Linux 和 macOS。

```sh
git clone https://github.com/smokecat/marginalia.git ~/.marginalia   # 位置随意
~/.marginalia/bin/marginalia setup
```

`setup` 会：

- 把 skills 软链到 `~/.agents/skills/` 和 `~/.claude/skills/`（遵守 `CLAUDE_CONFIG_DIR`）
- 把 `marginalia` 命令软链到 `~/.local/bin/`
- 为已安装的 Codex / Gemini CLI 写入全局入口托管块（目录不存在则跳过，装好工具后重跑即可）

升级：`git pull` 后重跑 `marginalia setup`，再在各项目里重跑 `marginalia init`。

## 快速开始

在项目根运行（或在 agent 里让它使用 `marginalia-init` skill）：

```sh
marginalia init
```

输出里的 `[ASK]` 需要你决定，按提示加对应选项重跑；`[CONFLICT]` / `[WARN]` 是未自动处理的情况。之后正常和 agent 对话即可：

- "这是个要做好几天的活，记录好下次接着做" → agent 建任务并维护接续指引
- 新会话里说"继续 xx 任务" → agent 读接续指引后直接干活，换一个工具也一样

新项目还可以用 `marginalia-kickoff` skill 走一遍需求 → 调研 → 选型 → 目录规划的启动引导。

## 命令参考

```
marginalia setup | uninstall
marginalia init [--git-init] [--update-spec] [--create-claude-md] [--migrate-memory] [目录]
marginalia task new <slug> [标题]
marginalia task list
marginalia task status <slug> <active|paused|blocked|done>
marginalia task archive <slug> [一句话结果] [--force]
marginalia --version
```

| init 选项 | 作用 |
|---|---|
| `--git-init` | 目录还不是 git 仓库时先 `git init` |
| `--update-spec` | 用最新模板覆盖 `.local/README.md` 和任务模板（旧版在 `.local` 的 git 历史里） |
| `--create-claude-md` | 项目只有 `AGENTS.md` 时创建内容为 `@AGENTS.md` 的 `CLAUDE.md`（**共享文件**，需提交） |
| `--migrate-memory` | 把 Claude 默认 auto memory 目录的内容复制进 `.local/memory/` |

`init` 是幂等的：缺的补上，失效的修复，托管块外的内容和已有的用户数据一律不覆盖。

## 推荐的项目指令结构

| 文件 | 内容 | 提交 |
|---|---|---|
| `AGENTS.md` | 共享的项目说明，所有 agent 都读 | 是 |
| `CLAUDE.md` | `@AGENTS.md`，加上 Claude 专属内容 | 是 |
| `CLAUDE.local.md` | 私有内容，marginalia 的入口托管块也在这里 | 否 |

## 兼容性

2026-10 的实测结果：

| 工具 | 读到入口 | 发现 skills | 接续任务 | 写入 .local |
|---|---|---|---|---|
| Claude Code 2.1.296 | ✅ | ✅ | ✅ | ✅ |
| Codex 0.162.1 | ✅ | ✅ | ✅ | ✅（workspace-write 沙箱下可以 commit `.local`） |
| Gemini CLI 0.63.0 | ⚠️ | ✅ | ✅ | 未测 |

**已知限制**

- Gemini CLI 的 `read_file` 会拒绝读取被 git 忽略的路径，读 `.local/` 要绕道其他工具。`respectGitIgnore` 是整个项目的开关，关掉会把 `node_modules` 等也暴露出来，所以 marginalia 不去改它。
- 从项目子目录启动 Claude Code 时，`CLAUDE.local.md` 里对上级 `AGENTS.md` 的 import 算外部 import，需要在审批对话框里确认一次。
- 模板和 skill 目前是中文。

## 卸载

```sh
marginalia uninstall
```

只移除 `setup` 创建的软链和全局入口托管块。各项目里的 `.local/`、`CLAUDE.local.md` 托管块和 exclude 规则不动，需要的话手动删除。

## 开发

```sh
scripts/check                                    # shellcheck + Python 语法 + bats；未安装时自动用 bunx/npx
MARGINALIA_TEST_BASH=/bin/bash scripts/check test   # 用指定的 bash 跑测试（如 macOS 自带的 3.2）
```

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE)
