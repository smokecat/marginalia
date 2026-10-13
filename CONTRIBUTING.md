# 参与贡献

欢迎提 issue 和 PR。动手做较大的改动之前，先开 issue 讨论方向。

## 开发环境

```sh
git clone https://github.com/smokecat/marginalia.git
cd marginalia
scripts/check     # shellcheck + Python 语法 + bats；没有全局安装时自动用 bunx/npx
```

测试会隔离 `HOME` 和 git 全局配置，不会读写你的真实环境。

## 代码约定

- **bash 3.2 兼容**：macOS 自带 bash 3.2，不要用关联数组、`mapfile`、`${var,,}` 等 bash 4+ 特性。CI 会在 macOS 上用 `/bin/bash` 跑一遍测试。
- **避开 GNU/BSD 差异**：文本、JSON、路径处理放进 `lib/helpers.py`（Python 3.8+，只用标准库），不要依赖 `sed -i`、`readlink -f`、`realpath -m` 这类在两个平台上行为不同的命令。
- **shellcheck 零警告**。
- **零痕迹**：除了 `--create-claude-md`，任何操作都不能修改主仓库中受版本控制的文件。
- **幂等**：重复运行 `init` / `setup` 不能产生新的变更，也不能覆盖用户数据。
- 改了行为就补测试（`test/marginalia.bats`）。

## 模板与 skill 的写法

`templates/` 和 `skills/` 是写给 agent 读的：

- 写目标和不变量，不规定步骤和频率；marginalia 不规定工作方法。
- 一条规则只写在一个地方：详细约定在 `templates/local/README.md`，入口托管块只放指引。
- frontmatter 只用 [Agent Skills](https://agentskills.io) 标准字段，保证各工具都能加载。

## 提交信息

使用 [Conventional Commits](https://www.conventionalcommits.org/)：`feat:`、`fix:`、`docs:`、`test:`、`refactor:`、`chore:`。用户能感知的变更同时更新 `CHANGELOG.md`。
