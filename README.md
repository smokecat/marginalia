# marginalia

[![CI](https://github.com/smokecat/marginalia/actions/workflows/ci.yml/badge.svg)](https://github.com/smokecat/marginalia/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**给 coding agent 的零痕迹私有工作区。** 在项目里放一个只有你本机可见的 `.margin/`（目录名可配置），让 Claude Code、Codex、Gemini CLI 等工具跨会话、跨工具地接续任务、共享项目经验——不往共享仓库里提交任何文件。

> *marginalia*：页边批注。在别人的书页边上写自己的笔记，书本身不变。

## 为什么

- **会话会断，上下文会丢。** 跨几天的工作需要一份"下一个会话读了就能接着干"的交接记录。
- **你会换工具。** 今天用 Claude、明天用 Codex，任务状态和踩过的坑应该放在同一个地方，而不是锁在某个工具的私有存储里。
- **仓库不一定是你的。** 在团队仓库里，你未必想（或被允许）提交 agent 相关的配置文件。marginalia 只写 git 不跟踪的文件，`git status` 始终干净。

marginalia **不规定工作方法**。它只负责把状态持久化、把入口接到各个工具上；怎么干活由 agent 自己判断。

## 工作原理

```
your-project/
├── .margin/                    # 独立 git 仓库，经 .git/info/exclude 排除
│   ├── README.md               # 约定说明，各 agent 首次操作前读它
│   ├── tasks/<slug>/README.md  # 跨会话任务；核心是「接续指引」
│   ├── tasks/archived/
│   ├── memory/MEMORY.md        # 各 agent 共享的项目经验库
│   ├── ops/YYYY-MM.md          # 线上操作记录
│   ├── todo.md
│   └── docs/ scripts/ templates/ out/ logs/ tmp/
├── CLAUDE.local.md             # Claude Code 的项目级入口（托管块）
└── .claude/settings.local.json # autoMemoryDirectory → .margin/memory
```

各 agent 拿到的是同一份核心约定（`templates/entry-core.md`），接入方式按各自的能力来：

| 工具 | 项目级上下文 | 全局入口（兜底） | skills | 经验库 |
|---|---|---|---|---|
| Claude Code | 项目内 `CLAUDE.local.md` 托管块 | — | `~/.claude/skills/`（软链） | auto memory 直接指向 `.margin/memory/` |
| Codex | 用户级 SessionStart hook（`~/.codex/hooks.json`）注入 | `~/.codex/AGENTS.md` 托管块（遵守 `CODEX_HOME`） | `~/.agents/skills/` | hook 注入 `MEMORY.md` 索引，按约定读写 |
| Gemini CLI | 用户级 SessionStart hook（`~/.gemini/settings.json`）注入 | `~/.gemini/GEMINI.md` 托管块（遵守 `GEMINI_CLI_HOME`） | `~/.agents/skills/` | 同上 |

hook 调用的是 `marginalia hook session-start <agent>`：在会话目录找到工作区时，注入核心约定、活跃任务和经验索引；不在 marginalia 项目里时什么都不输出。注入的内容也可以用 `marginalia context` 直接查看，没有 hook 的 agent 可以手动跑它。

默认启用本机已安装的 agent（配置目录存在即算）；要显式指定，用 `marginalia config --user agents claude,codex`，然后重跑 `setup`。

几个关键设计：

- **零痕迹**：只写 `.git/info/exclude`、`.git/config`（记录目录名）、`CLAUDE.local.md`、`.claude/settings.local.json` 和工作区目录，不修改主仓库中任何受版本控制的文件。
- **约定单一来源**：所有入口（Claude 托管块、hook 注入、`marginalia context`）都由同一份核心约定渲染；详细规范只在工作区的 `README.md`。
- **共享经验库**：把 Claude Code 的 auto memory 目录指向 `.margin/memory/`，Claude 照常自动维护；其他 agent 在会话开头拿到 `MEMORY.md` 索引，按同一结构读写。
- **按能力接入**：加一个 agent 就是在 `bin/marginalia` 的适配器函数里补一个分支（配置目录、skills 目录、全局入口、hook、项目级入口，没有的能力留空）。
- **不挡住 AGENTS.md**：项目里只要有 `CLAUDE.local.md`，Claude Code 默认就不再读 `AGENTS.md`。项目没有 `CLAUDE.md` 时，托管块里会带 `@AGENTS.md` 兜底。
- **worktree 共享**：worktree 里的工作区目录是指向主工作区的软链，和 Claude auto memory 跨 worktree 共享的行为一致。
- **任务状态只存一处**：任务 README 的 frontmatter 就是状态，没有另外的索引文件需要同步。

## 安装

依赖：bash ≥ 3.2、git ≥ 2.31、python3 ≥ 3.8（只用标准库）。支持 Linux 和 macOS。

```sh
git clone https://github.com/smokecat/marginalia.git ~/.local/share/marginalia   # 位置随意
~/.local/share/marginalia/bin/marginalia setup
```

`setup` 会：

- 把 skills 软链到 `~/.agents/skills/` 和 `~/.claude/skills/`（遵守 `CLAUDE_CONFIG_DIR`）
- 把 `marginalia` 命令软链到 `~/.local/bin/`
- 为启用的 Codex / Gemini CLI 写入全局入口托管块和 SessionStart hook（工具未安装则跳过，装好后重跑即可）；多个全局入口软链到同一份文件时只写一次
- Codex 首次启动时会提示审核这个 hook（Hooks need review），确认后生效；Gemini 只在受信任的文件夹里运行 hook

升级：`git pull` 后重跑 `marginalia setup`，再在各项目里重跑 `marginalia init`。还在用 `.local/` 的旧项目见[从 `.local` 迁移](#从-local-迁移)。

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
marginalia init [--dir 名字] [--git-init] [--update-spec] [--create-claude-md] [--migrate-memory] [目录]
marginalia migrate [--to 名字] [--dry-run] [目录]
marginalia config [--list]
marginalia config [--system|--user|--project] [--unset] dir [名字]
marginalia config [--system|--user] [--unset] agents [auto|claude,codex,gemini]
marginalia context [目录]
marginalia task new <slug> [标题]
marginalia task list [--json] [--archived]
marginalia task show <slug> --json
marginalia task status <slug> <active|paused|blocked|done>
marginalia task archive <slug> [一句话结果] [--force]
marginalia --version
```

| init 选项 | 作用 |
|---|---|
| `--dir <名字>` | 本项目使用的目录名（不给则用默认值，见下文「目录名」） |
| `--git-init` | 目录还不是 git 仓库时先 `git init` |
| `--update-spec` | 用最新模板覆盖工作区的 `README.md` 和任务模板（旧版在工作区的 git 历史里） |
| `--create-claude-md` | 项目只有 `AGENTS.md` 时创建内容为 `@AGENTS.md` 的 `CLAUDE.md`（**共享文件**，需提交） |
| `--migrate-memory` | 把 Claude 默认 auto memory 目录的内容复制进工作区的 `memory/` |

项目级入口只为启用的 agent 落地（目前只有 Claude Code 有项目级入口）；以前已经落地过的入口会继续维护。

`init` 是幂等的：缺的补上，失效的修复，托管块外的内容和已有的用户数据一律不覆盖。

`--json` 给其他程序用：`task list --json` 输出任务库身份（`store.root`、`store.id`、`store.dir`、`store.project`）和每个任务的 slug、标题、状态、日期、是否归档、路径与接续指引四个字段；`task show <slug> --json` 另带目标、待办计数和接续指引全文。归档只移动目录，slug 不变，可以当作稳定的引用。

写任务的命令只提交它自己改动的路径，你另外暂存在工作区里的改动不会被一起提交。文件已改但 commit 失败（hook、签名等）时退出码为 4；不在 git 项目中或项目没有工作区时退出码为 5。

## 目录名

工作区目录名默认是 `.margin`，可以在几个级别上设置（越往下优先级越高）：

| 级别 | 位置 | 设置 |
|---|---|---|
| 内置 | `.margin` | — |
| 系统 | `/etc/marginalia/config` | `sudo marginalia config --system dir <名字>` |
| 用户 | `~/.marginalia/config` | `marginalia config --user dir <名字>` |
| 环境变量 | `MARGINALIA_DIR` | 只覆盖默认值 |
| 项目 | 主仓库 `.git/config` 的 `marginalia.dir` | `marginalia init --dir <名字>` |

配置文件是 git config 格式（`[marginalia]` 段的 `dir`）。`marginalia config --list` 列出各级的值和本项目实际用的名字。

`init` 会把实际用的目录名写进项目配置，之后再改默认值，已有项目不受影响；要给已有工作区改名，用 `migrate`。环境变量不覆盖项目配置，避免 shell 里的一个变量让所有已有项目找不到工作区。

Codex 和 Gemini CLI 的全局入口按用户默认值生成，改了默认值后重跑 `marginalia setup`。

## 从 `.local` 迁移

旧版 marginalia 的工作区叫 `.local/`。这样的项目不迁移也能照常用（没有项目配置、但 `.local/` 是 marginalia 工作区时自动识别）；重跑 `init` 会把 `.local` 写进项目配置，并提示迁移：

```sh
marginalia migrate --dry-run    # 先看计划
marginalia migrate              # 改为当前默认目录名；--to <名字> 指定其他名字
```

`migrate` 移动工作区目录，同步更新 exclude 规则、各 worktree 的软链、`CLAUDE.local.md` 托管块、`.claude/settings.local.json`、`.claude/` 和 `.agents/` 下指进工作区的软链（如 `local-*` 私有 skill）和项目配置，没改过的规范文件随之更新。任务库身份（`store.id`）保持不变，trine 里已有的会话关联不受影响。中途失败的话重跑就能继续；`--to .local` 可以迁回去。

任务、经验等正文里写着的旧路径不会被改写，`migrate` 会把这些文件列出来，按需手动修改。迁移后本项目里正在运行的 agent 会话需要重启（auto memory 路径变了）。

工作区里如果放了脚本，迁移前留意三类东西：启动时就记下绝对路径的常驻进程（tmux 里的循环任务等），迁移后要重启；脚本里写死的旧目录名（在上面的清单里）；Python venv 等把绝对路径写进 shebang 的环境，迁移后要重建（如 `uv sync`）。

## 在 trine 里使用

[trine](https://github.com/smokecat/trine)（Claude Code 的自托管远程界面）可以加载 marginalia 的扩展：在会话页查看本项目的任务、把会话关联到任务、一键开新会话接续。扩展在 `integrations/trine/`，需要 trine agent 0.16.0 及以上，在 agent 所在的机器上注册：

```sh
trine-agent ext add <marginalia 目录>/integrations/trine
```

扩展通过同一份 marginalia 的 `--json` 读数据，「标为完成」「归档」也调用 marginalia 命令，不直接改文件。它看不到对话内容，只拿到会话的目录和关联。权限（直接发送、新建会话要不要确认）在 trine 的「设置 → 扩展」里设置。

## 推荐的项目指令结构

| 文件 | 内容 | 提交 |
|---|---|---|
| `AGENTS.md` | 共享的项目说明，所有 agent 都读 | 是 |
| `CLAUDE.md` | `@AGENTS.md`，加上 Claude 专属内容 | 是 |
| `CLAUDE.local.md` | 私有内容，marginalia 的入口托管块也在这里 | 否 |

## 兼容性

2026-11 的实测结果：

| 工具 | 读到入口 | 会话开头注入 | 发现 skills | 接续任务 | 写入工作区 |
|---|---|---|---|---|---|
| Claude Code 2.1.308 | ✅ | —（项目级 `CLAUDE.local.md`） | ✅ | ✅ | ✅ |
| Codex 0.162.1 | ✅ | ✅（SessionStart hook，需审核一次） | ✅ | ✅ | ✅（workspace-write 沙箱下可以在工作区内 commit） |
| Gemini CLI 0.63.0 | ⚠️ | ✅（SessionStart hook，受信任文件夹） | ✅ | ✅ | 未测 |

**已知限制**

- Gemini CLI 的 `read_file` 会拒绝读取被 git 忽略的路径，读工作区要绕道其他工具（hook 注入的上下文不受影响）。`respectGitIgnore` 是整个项目的开关，关掉会把 `node_modules` 等也暴露出来，所以 marginalia 不去改它。需要的话可以在项目的 `.geminiignore` 里加 `!.margin/` 和 `!.margin/**` 放行，并把 `.geminiignore` 也加进 `.git/info/exclude`——这要往项目里放文件，marginalia 不自动做。
- Codex 的 hook 要先在 TUI 里审核才会运行，`codex exec` 里未审核的 hook 直接跳过；hook 命令变了（如 `~/.local/bin` 位置变了）需要重新审核。没有生效时，全局入口托管块会提示 agent 自己运行 `marginalia context`。
- Gemini 的 `settings.json` 带注释（JSONC）时 marginalia 无法安全改写，会报 `[CONFLICT]`；可以参照 `marginalia setup` 在干净文件里写出的结构手动添加。
- Codex、Gemini 自己的原生记忆（`~/.codex/memories`、`~/.gemini/tmp/<项目>/memory`）路径固定、由工具自己管理，marginalia 不去接管，共享经验以 `.margin/memory/` 为准。
- 从项目子目录启动 Claude Code 时，`CLAUDE.local.md` 里对上级 `AGENTS.md` 的 import 算外部 import，需要在审批对话框里确认一次。
- 模板和 skill 目前是中文。

## 卸载

```sh
marginalia uninstall
```

只移除 `setup` 创建的软链、全局入口托管块和 SessionStart hook。各项目里的工作区目录、`CLAUDE.local.md` 托管块、exclude 规则和项目配置不动，需要的话手动删除。

## 开发

```sh
scripts/check                                    # shellcheck + Python 语法 + bats；未安装时自动用 bunx/npx
MARGINALIA_TEST_BASH=/bin/bash scripts/check test   # 用指定的 bash 跑测试（如 macOS 自带的 3.2）
```

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE)
