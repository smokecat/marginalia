# .local — 私有工作区

本目录只在本机可见（通过 `.git/info/exclude` 排除，不改主仓库任何文件），是一个独立的 git 仓库（tmp/logs/out 除外）。用于跨会话保存任务状态、项目经验和 ops 记录，不规定工作方法。本文件是这些约定的唯一详细版本，适用于所有 agent 工具。

## 目录

| 路径 | 用途 |
|---|---|
| tasks/<slug>/ | 跨会话任务，README.md 为入口 |
| tasks/archived/ | 已完成任务 |
| memory/ | 项目经验库，各 agent 共享（见下文） |
| todo.md | 一句话待办/随想（`- [ ] YYYY-MM-DD 内容`），成型后升级为 task |
| ops/YYYY-MM.md | 线上操作记录 |
| docs/、scripts/ | 私有文档、本地脚本 |
| templates/ | 任务模板 |
| out/、logs/、tmp/ | 产物/日志/临时文件，不入 git |

## 任务

机械操作用 `marginalia task` 命令（`new` / `list` / `archive` / `status`），它会顺带完成 commit。

**何时建**：工作会跨会话、或有需要留痕的决策时建任务；本会话能做完的事不建。slug 用 kebab-case。

**README**：frontmatter 里的 `status`（active | paused | blocked | done）是任务状态的唯一来源，没有单独的索引文件。

**接续指引**是任务 README 的核心：新会话只读这一节就能直接干活。「下一步」必须是具体动作（如"跑 X 测试确认 Y"），不写"继续开发"。

**何时同步**：在检查点更新 README（包括接续指引和 `updated`）并 commit——阶段完成、做了关键决策、范围变化、用户说暂停、或会话即将结束。判断标准是"如果会话此刻中断，下一个会话（可能是另一个 agent 工具）会不会丢东西"。进度历史看 .local 的 git log，README 里不另记流水账。

**范围**：发现做不完时拆出新任务并写明，不悄悄缩小已承诺的范围。

**接续**：读任务 README（重点接续指引）→ 按需读任务目录里的其他文件 → 继续。不凭记忆接续。同一任务同一时间只由一个 agent 推进。

## 经验库 memory/

存放下次能省时间的持久经验：项目怪癖、踩坑正解、已验证的用户偏好。一次性偶发错误、常识、代码库本身已记录的事实不记。

- 结构：`MEMORY.md` 是索引，每条一行 `- [标题](file.md) — 一句话`；每条经验一个文件，带 frontmatter（`name` 用 kebab-case 短名，与文件名一致；`description`；`metadata.type`: user | feedback | project | reference）
- Claude Code 的 auto memory 已指向本目录，会自动维护；其他 agent 开工前读 `MEMORY.md`，按需读具体条目，写入时遵循同样的结构
- 有新认识时更新旧条目，不另起一条；被证伪的删除

## ops 记录

线上操作（部署、迁移、配置变更、数据修复）后追加到 `ops/YYYY-MM.md`：

```markdown
### YYYY-MM-DD HH:MM 操作标题
- 环境：
- 操作：（具体命令/步骤）
- 结果：
- 回滚：（如何撤销）
```

## git

- commit message 前缀：`task(<slug>):` / `archive(<slug>):` / `memory:` / `ops:` / `todo:` / `docs:` / `chore:`
- .local 内容永不进主仓库，也不出现在 PR、共享文档等对外产物中
- 清理空间时直接删 tmp/logs/out 里的旧文件；已归档任务可在 git 历史中找回
