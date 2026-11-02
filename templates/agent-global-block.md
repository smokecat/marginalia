## 私有工作区（{{DIR}}/）

在 git 项目中开始工作前，检查项目根是否有 `{{DIR}}/README.md`（个别项目配置了别的目录名，`git config marginalia.dir` 可查；旧项目可能仍是 `.local/`）。上下文里已有「私有工作区」约定（项目级入口或会话开头的注入）时以它为准；没有时，运行 `marginalia context` 获取（命令不可用就先读 `{{DIR}}/README.md` 和 `{{DIR}}/memory/MEMORY.md`）。`{{DIR}}/` 用于跨会话保存任务状态（任务接续）、项目经验和 ops 记录，不规定工作方法，内容永不进入主仓库或对外产物。
