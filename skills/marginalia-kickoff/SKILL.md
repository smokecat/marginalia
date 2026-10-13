---
name: marginalia-kickoff
description: 新项目启动引导：需求澄清 → 背景盘点 → 技术调研 → 选型决策 → 目录规划，产出存入 .local/tasks/project-kickoff/，可中断接续。只在用户明确要求时使用，适合预计一周以上的项目（小项目直接开干）。
---

# marginalia-kickoff

## 前置

- 项目没有 .local/ → 说明需要先初始化，征得同意后按 marginalia-init 执行，再继续
- `.local/tasks/project-kickoff/` 已存在 → 读它的接续指引，从中断处继续
- 否则 `marginalia task new project-kickoff 项目启动`，待办预填下面五个阶段

kickoff 本身就是项目的第一个任务。每个阶段结束时落盘、刷新接续指引并 commit。

## 产出

`.local/tasks/project-kickoff/` 下：REQUIREMENTS.md、RESEARCH.md（以及每个方向一份 research-<方向>.md）、DECISIONS.md、STRUCTURE.md。

## 阶段

1. **需求澄清**：定位（给谁解决什么问题）、目标用户与场景、MVP 功能和以后再做的功能、非目标、硬约束（时间/平台/预算/合规）。分批提问，每批不超过 4 个；用户已经回答过的（参数、会话、已有文档里有的）不再问。整理成 REQUIREMENTS.md 并复述给用户确认。
2. **背景盘点**：可复用的资产、类似经验和教训、想参考或想避开的竞品。并入 REQUIREMENTS.md。
3. **技术调研**：提炼 2-4 个关键方向，请用户确认；然后并行调研（工具支持子 agent 时并行派发），每个调研者要拿到方向、关键问题、需求摘要和输出路径。写 RESEARCH.md 汇总各方向的 TL;DR。
4. **选型决策**：每个选型点给出推荐和备选，让用户逐项拍板。调研可以并行，决策必须由用户逐项决定。记入 DECISIONS.md（决定 / 理由 / 否弃项）。
5. **目录规划**：给出目录树和每个顶级目录的职责，写入 STRUCTURE.md。问用户是否现在创建脚手架。

## 收尾

- 起草共享的项目说明：内容写进 `AGENTS.md`（定位、技术栈、目录职责、开发命令；不写私有内容），并建 `CLAUDE.md`，内容为 `@AGENTS.md`。用户确认后写入；文件已存在时只列出建议补充的点
- 把 kickoff 任务标为 done 并归档（或按用户意愿保留为项目总纲）
- 建议第一批开发任务，用户确认后逐个用 `marginalia task new` 创建
