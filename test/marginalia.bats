#!/usr/bin/env bats
# 运行：bats test/   用指定 bash 运行（如 macOS 自带的 3.2）：MARGINALIA_TEST_BASH=/bin/bash bats test/

setup() {
  REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)
  # 隔离 HOME 与 git 全局配置，测试不读写真实环境
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  git config --global user.name test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false
  unset CLAUDE_CONFIG_DIR CODEX_HOME
  mkdir -p "$BATS_TEST_TMPDIR/proj"
  P=$(cd "$BATS_TEST_TMPDIR/proj" && pwd -P)
}

mg() { "${MARGINALIA_TEST_BASH:-bash}" "$REPO/bin/marginalia" "$@"; }
init_repo() { git -C "$1" init -q; }
has() { [[ "$output" == *"$1"* ]] || { echo "输出中缺少：$1"; echo "$output"; return 1; }; }
lacks() { [[ "$output" != *"$1"* ]] || { echo "输出中不应有：$1"; echo "$output"; return 1; }; }

# ------------------------------------------------------------------ 基础

@test "--version 输出 VERSION 文件中的版本" {
  run mg --version
  [ "$status" -eq 0 ]
  [ "$output" = "marginalia $(cat "$REPO/VERSION")" ]
}

@test "未知命令返回非零并打印用法" {
  run mg bogus
  [ "$status" -eq 1 ]
  has "用法"
}

# ------------------------------------------------------------------ init

@test "init：非 git 目录返回 3 并询问，--git-init 后成功" {
  run mg init "$P"
  [ "$status" -eq 3 ]
  has "[ASK]"
  run mg init --git-init "$P"
  [ "$status" -eq 0 ]
  [ -d "$P/.git" ] && [ -d "$P/.local/.git" ]
}

@test "init：落地骨架、exclude、CLAUDE.local.md、memory 设置，主仓库保持干净" {
  init_repo "$P"
  run mg init "$P"
  [ "$status" -eq 0 ]
  for f in README.md .gitignore todo.md templates/task.md memory/MEMORY.md; do [ -f "$P/.local/$f" ]; done
  for d in tasks/archived docs ops scripts out logs tmp; do [ -d "$P/.local/$d" ]; done
  [ "$(git -C "$P/.local" log --oneline | wc -l | tr -d ' ')" = 1 ]
  grep -qxF .local "$P/.git/info/exclude"
  grep -qxF CLAUDE.local.md "$P/.git/info/exclude"
  grep -q "marginalia:start" "$P/CLAUDE.local.md"
  grep -qxF "@AGENTS.md" "$P/CLAUDE.local.md"       # 没有 CLAUDE.md 时兜底 import
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["autoMemoryDirectory"]==sys.argv[2]' \
    "$P/.claude/settings.local.json" "$P/.local/memory"
  [ -z "$(git -C "$P" status --porcelain)" ]
}

@test "init：幂等，重跑没有新建也没有新 commit" {
  init_repo "$P"
  mg init "$P"
  run mg init "$P"
  [ "$status" -eq 0 ]
  lacks "[CREATED]"
  lacks "[COMMITTED]"
  [ "$(git -C "$P/.local" log --oneline | wc -l | tr -d ' ')" = 1 ]
  [ "$(grep -c '^\.local$' "$P/.git/info/exclude")" = 1 ]
}

@test "init：只有 AGENTS.md 时询问，--create-claude-md 后托管块不再带 import" {
  init_repo "$P"
  echo shared > "$P/AGENTS.md"
  run mg init "$P"
  has "--create-claude-md"
  grep -qxF "@AGENTS.md" "$P/CLAUDE.local.md"
  run mg init --create-claude-md "$P"
  [ "$(cat "$P/CLAUDE.md")" = "@AGENTS.md" ]
  ! grep -qxF "@AGENTS.md" "$P/CLAUDE.local.md"
}

@test "init：CLAUDE.md 没有 import AGENTS.md 时警告" {
  init_repo "$P"
  echo shared > "$P/AGENTS.md"
  echo "# mine" > "$P/CLAUDE.md"
  run mg init "$P"
  has "[WARN] CLAUDE.md 没有 import AGENTS.md"
}

@test "init：保留 CLAUDE.local.md 块外内容与 settings.local.json 其他字段" {
  init_repo "$P"
  mkdir -p "$P/.claude"
  printf '# 私有笔记\n保留这行\n' > "$P/CLAUDE.local.md"
  echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$P/.claude/settings.local.json"
  run mg init "$P"
  has "[APPENDED] CLAUDE.local.md"
  [ "$(head -2 "$P/CLAUDE.local.md")" = $'# 私有笔记\n保留这行' ]
  grep -q 'Bash(ls:\*)' "$P/.claude/settings.local.json"
  grep -q autoMemoryDirectory "$P/.claude/settings.local.json"
}

@test "init：托管块内容被改动后会恢复，块外内容不变" {
  init_repo "$P"
  mg init "$P"
  printf '尾部内容\n' >> "$P/CLAUDE.local.md"
  sed 's/私有工作区（.local\/）/被改掉/' "$P/CLAUDE.local.md" > "$P/x" && mv "$P/x" "$P/CLAUDE.local.md"
  run mg init "$P"
  has "[UPDATED] CLAUDE.local.md"
  grep -q "私有工作区（.local/）" "$P/CLAUDE.local.md"
  [ "$(tail -1 "$P/CLAUDE.local.md")" = "尾部内容" ]
}

@test "init：autoMemoryDirectory 指向别处时报告冲突，不修改" {
  init_repo "$P"
  mkdir -p "$P/.claude"
  echo '{"autoMemoryDirectory":"/elsewhere"}' > "$P/.claude/settings.local.json"
  run mg init "$P"
  has "[CONFLICT]"
  grep -q '/elsewhere' "$P/.claude/settings.local.json"
}

@test "init：规范模板有差异时询问，--update-spec 后覆盖并 commit" {
  init_repo "$P"
  mg init "$P"
  echo "本地改动" >> "$P/.local/README.md"
  git -C "$P/.local" commit -qam "local edit"
  run mg init "$P"
  has "[ASK] .local/README.md"
  run mg init --update-spec "$P"
  has "[UPDATED] .local/README.md"
  has "[COMMITTED]"
  cmp -s "$P/.local/README.md" "$REPO/templates/local/README.md"
}

@test "init：私有路径已被主仓库跟踪时报告冲突" {
  init_repo "$P"
  echo x > "$P/CLAUDE.local.md"
  git -C "$P" add CLAUDE.local.md
  run mg init "$P"
  has "[CONFLICT] 以下私有路径已被主仓库跟踪"
}

@test "init：迁移 Claude 默认 auto memory" {
  init_repo "$P"
  local old="$HOME/.claude/projects/$(printf '%s' "$P" | sed 's/[^A-Za-z0-9]/-/g')/memory"
  mkdir -p "$old"
  printf -- '- [坑](trap.md) — 测试\n' > "$old/MEMORY.md"
  echo trap > "$old/trap.md"
  run mg init "$P"
  has "--migrate-memory"
  run mg init --migrate-memory "$P"
  has "[MIGRATED]"
  grep -q "trap.md" "$P/.local/memory/MEMORY.md"
  [ -f "$P/.local/memory/trap.md" ] && [ -f "$old/trap.md" ]
}

@test "init：worktree 要求主工作区先初始化，之后共享同一个 .local" {
  init_repo "$P"
  git -C "$P" commit -q --allow-empty -m init
  git -C "$P" worktree add -q "$BATS_TEST_TMPDIR/wt"
  local wt
  wt=$(cd "$BATS_TEST_TMPDIR/wt" && pwd -P)
  run mg init "$wt"
  [ "$status" -ne 0 ]
  has "先在主工作区运行"
  mg init "$P"
  run mg init "$wt"
  [ "$status" -eq 0 ]
  [ "$(readlink "$wt/.local")" = "$P/.local" ]
  grep -q "\"$P/.local/memory\"" "$wt/.claude/settings.local.json"
  [ -z "$(git -C "$wt" status --porcelain)" ]
  (cd "$wt" && mg task new from-wt >/dev/null)
  [ -f "$P/.local/tasks/from-wt/README.md" ]
}

# ------------------------------------------------------------------ task

@test "task：项目没有 .local 时报错" {
  init_repo "$P"
  cd "$P"
  run mg task list
  [ "$status" -ne 0 ]
  has "先运行 marginalia init"
}

@test "task：new / list / status / archive 全流程，各自 commit" {
  init_repo "$P"
  mg init "$P"
  mkdir -p "$P/src" && cd "$P/src"
  run mg task new fix-login '修复登录 & 会话 "问题" \1'
  [ "$status" -eq 0 ]
  grep -qxF '# 修复登录 & 会话 "问题" \1' "$P/.local/tasks/fix-login/README.md"
  sed 's/^- \*\*当前状态\*\*：$/- **当前状态**：定位到 token 刷新/' "$P/.local/tasks/fix-login/README.md" > x && mv x "$P/.local/tasks/fix-login/README.md"

  run mg task list
  has "fix-login"
  has "定位到 token 刷新"
  has "已归档：0 个"

  run mg task status fix-login wip
  [ "$status" -ne 0 ]
  run mg task status fix-login blocked
  [ "$status" -eq 0 ]
  grep -qx "status: blocked" "$P/.local/tasks/fix-login/README.md"

  run mg task archive fix-login
  [ "$status" -ne 0 ]
  has "--force"
  run mg task archive fix-login 修好了 token 刷新 --force
  [ "$status" -eq 0 ]
  local f="$P/.local/tasks/archived/fix-login/README.md"
  grep -qx "result: 修好了 token 刷新" "$f"
  grep -q "^archived: " "$f"

  run mg task list
  has "没有未归档任务"
  has "已归档：1 个"
  [ -z "$(git -C "$P/.local" status --porcelain)" ]
  [ "$(git -C "$P/.local" log --oneline | wc -l | tr -d ' ')" = 4 ]
}

@test "task：拒绝非法 slug 和重复任务" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  run mg task new Bad_Slug
  [ "$status" -ne 0 ]
  mg task new ok-task
  run mg task new ok-task
  [ "$status" -ne 0 ]
  has "任务已存在"
}

@test "task：在 .local 目录内也能定位项目" {
  init_repo "$P"
  mg init "$P"
  cd "$P/.local/tasks"
  run mg task list
  [ "$status" -eq 0 ]
}

@test "task：status / archive 也拒绝非法 slug（不能逃出 tasks 目录）" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mkdir -p "$P/.local/x" && printf -- '---\nstatus: active\n---\n# x\n' > "$P/.local/x/README.md"
  run mg task status ../x done
  [ "$status" -ne 0 ]
  has "kebab-case"
  grep -qx "status: active" "$P/.local/x/README.md"
  run mg task archive ../x --force
  [ "$status" -ne 0 ]
  has "kebab-case"
}

@test "task：commit 只包含本次操作的路径，用户另外暂存的改动保持暂存" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  echo note >> "$P/.local/todo.md"
  git -C "$P/.local" add todo.md
  mg task new keep-staged
  [ "$(git -C "$P/.local" diff --cached --name-only)" = "todo.md" ]
  ! git -C "$P/.local" show --name-only --format= HEAD | grep -q todo.md
}

@test "task：重复归档已归档的任务不报错" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mg task new twice
  mg task archive twice --force
  run mg task archive twice --force
  [ "$status" -eq 0 ]
  has "已归档"
}

@test "task list --json / task show --json：机器可读，含接续指引与任务库身份" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mg task new alpha 'Alpha 任务'
  mg task new beta
  sed 's/^- \*\*下一步\*\*：.*$/- **下一步**：跑测试/' "$P/.local/tasks/alpha/README.md" > x && mv x "$P/.local/tasks/alpha/README.md"
  mg task status beta done
  mg task archive beta
  run mg task list --json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["v"] == 1 and len(d["store"]["id"]) == 12, d
assert [t["slug"] for t in d["tasks"]] == ["alpha"], d
t = d["tasks"][0]
assert t["title"] == "Alpha 任务" and t["status"] == "active" and t["archived"] is False
assert t["resume"]["next"] == "跑测试" and t["resume"]["state"] == "", t
assert t["path"] == ".local/tasks/alpha/README.md"
assert d["archivedCount"] == 1
PY
  run mg task list --json --archived
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); a=[t for t in d["tasks"] if t["archived"]]; assert [t["slug"] for t in a]==["beta"] and a[0]["path"]==".local/tasks/archived/beta/README.md"' "$output"
  run mg task show beta --json
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; t=json.loads(sys.argv[1])["task"]; assert t["archived"] and "todo" in t and "goal" in t' "$output"
  run mg task show ../etc --json
  [ "$status" -ne 0 ]
}

# ------------------------------------------------------------------ trine 扩展

ext() { # <op> <json>
  printf '%s' "$2" | TRINE_EXT_DIR="$REPO/integrations/trine" python3 "$REPO/integrations/trine/bin/trine-ext" "$1"
}

@test "trine 扩展：没有 .local 时返回空视图而不是报错" {
  init_repo "$P"
  cd "$P"
  run ext view '{"op":"view","point":"sessionPanel","context":{"cwd":"x","linkedSessions":[]}}'
  [ "$status" -eq 0 ]
  has "没有启用 marginalia"
}

@test "trine 扩展：视图按关联 / 状态分组，动作与契约一致" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mg task new alpha 'Alpha 任务'
  mg task new beta
  mg task status beta paused
  local store
  store=$(mg task list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["store"]["id"])')
  mkdir -p "$P/src"
  run ext view '{"op":"view","point":"sessionPanel","context":{"cwd":"'"$P/src"'","session":{"id":"s1","links":[{"ref":"'"$store"':beta","label":"b"}]},"linkedSessions":[{"id":"s1","links":[{"ref":"'"$store"':beta","label":"b"}]},{"id":"other","links":[{"ref":"elsewhere:beta","label":"b"}]}]}}'
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json, sys
v = json.loads(sys.argv[1])["view"]
secs = {s["id"]: s for s in v["sections"]}
assert [i["id"] for i in secs["linked"]["items"]] == ["beta"], secs
assert secs["linked"]["items"][0]["sessions"] == ["s1"]   # 别的任务库里的同名任务不算
alpha = secs["active"]["items"][0]
ids = [a["id"] for a in alpha["actions"]]
assert ids[:3] == ["resume-new", "resume-here", "insert"], ids
new = alpha["actions"][0]["effects"][0]
assert new["type"] == "session.create" and new["prompt"] == "继续 alpha 任务"
assert new["links"][0]["label"] == "Alpha 任务" and new["links"][0]["ref"].endswith(":alpha")
# 会话开在 src/ 里：插入的引用相对会话目录
assert alpha["actions"][2]["effects"][0]["text"] == "../.local/tasks/alpha/README.md", alpha["actions"][2]
PY
}

@test "trine 扩展：badge、pick（含输入框入口、新建会话）与 action" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mg task new alpha 'Alpha 任务'
  local store
  store=$(mg task list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["store"]["id"])')
  run ext badge '{"op":"badge","context":{"session":{"id":"s","links":[{"ref":"'"$store"':alpha","label":"old"}]}}}'
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["badge"]["text"]=="进行中" and d["links"][0]["label"]=="Alpha 任务", d' "$output"
  run ext pick '{"op":"pick","point":"composerAction","context":{},"args":{"query":"alp"}}'
  python3 -c 'import json,sys; i=json.loads(sys.argv[1])["items"]; assert [e["type"] for e in i[0]["effects"]]==["prompt.insert","links.add"], i' "$output"
  run ext pick '{"op":"pick","point":"newSession","context":{"cwd":"'"$P"'"}}'
  python3 -c 'import json,sys; i=json.loads(sys.argv[1])["items"]; assert i[0]["effects"]==[{"type":"prompt.insert","text":"继续 alpha 任务"}] and i[0]["link"]["ref"].endswith(":alpha"), i' "$output"
  run ext action '{"op":"action","context":{},"args":{"actionId":"status","params":{"slug":"alpha","status":"done"}}}'
  [ "$status" -eq 0 ]
  grep -qx "status: done" "$P/.local/tasks/alpha/README.md"
  run ext action '{"op":"action","context":{},"args":{"actionId":"archive","params":{"slug":"alpha"}}}'
  [ -d "$P/.local/tasks/archived/alpha" ]
  run ext action '{"op":"action","context":{},"args":{"actionId":"archive","params":{"slug":"alpha"}}}'
  has '"ok": true'
}

@test "trine 扩展：缺 frontmatter 的任务进「无法读取」，不静默消失" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mkdir -p "$P/.local/tasks/broken" && echo '# 没有 frontmatter' > "$P/.local/tasks/broken/README.md"
  run mg task list --json
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["tasks"]==[] and d["errors"][0]["slug"]=="broken", d' "$output"
  run ext view '{"op":"view","point":"workspacePanel","context":{"cwd":"'"$P"'","linkedSessions":[]}}'
  python3 -c 'import json,sys; s=json.loads(sys.argv[1])["view"]["sections"]; assert s[-1]["id"]=="errors" and s[-1]["items"][0]["title"]=="broken", s' "$output"
}

@test "trine 扩展：任务很多时按输出预算截断，不超过 trine 的 512 KB 上限" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  python3 - "$P/.local/tasks" <<'PY'
import os, sys
for i in range(200):
    d = os.path.join(sys.argv[1], "t%03d" % i)
    os.makedirs(d)
    open(os.path.join(d, "README.md"), "w").write("---\nstatus: active\nupdated: 2026-10-21\n---\n# 任务 %d\n\n## 接续指引\n\n- **下一步**：%s\n" % (i, "很长的下一步" * 120))
PY
  ext view '{"op":"view","point":"workspacePanel","context":{"cwd":"'"$P"'","linkedSessions":[]}}' > "$BATS_TEST_TMPDIR/out.json"
  [ "$(wc -c < "$BATS_TEST_TMPDIR/out.json")" -lt 524288 ]
  python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["view"]; assert v["title"].startswith("任务太多") and v["sections"][0]["items"], v.get("title")' "$BATS_TEST_TMPDIR/out.json"
}

@test "task archive：已归档但上次 commit 失败时，重跑补交" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mg task new late
  mv "$P/.local/tasks/late" "$P/.local/tasks/archived/late"
  run mg task archive late --force
  [ "$status" -eq 0 ]
  [ -z "$(git -C "$P/.local" status --porcelain)" ]
}

@test "task list --archived：文本输出也列出已归档任务" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mg task new gone
  mg task archive gone 搞定 --force
  run mg task list --archived
  has "gone"
  has "archived"
}

# ------------------------------------------------------------------ setup / uninstall

@test "setup：建立软链，只为已安装的工具写全局入口，幂等" {
  mkdir -p "$HOME/.codex"
  printf '# 我自己的 Codex 说明\n' > "$HOME/.codex/AGENTS.md"
  run mg setup
  [ "$status" -eq 0 ]
  for s in marginalia-init marginalia-task marginalia-kickoff; do
    [ "$(readlink "$HOME/.agents/skills/$s")" = "$REPO/skills/$s" ]
    [ "$(readlink "$HOME/.claude/skills/$s")" = "$REPO/skills/$s" ]
  done
  [ "$(readlink "$HOME/.local/bin/marginalia")" = "$REPO/bin/marginalia" ]
  grep -q "marginalia:start" "$HOME/.codex/AGENTS.md"
  [ ! -e "$HOME/.gemini" ]
  run mg setup
  lacks "[CREATED]"
}

@test "setup：遵守 CODEX_HOME 与 CLAUDE_CONFIG_DIR" {
  export CODEX_HOME="$BATS_TEST_TMPDIR/codex" CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  mkdir -p "$CODEX_HOME"
  mg setup
  [ -L "$CLAUDE_CONFIG_DIR/skills/marginalia-task" ]
  grep -q "marginalia:start" "$CODEX_HOME/AGENTS.md"
}

@test "uninstall：移除软链和全局入口，保留用户自己的内容" {
  mkdir -p "$HOME/.codex" "$HOME/.gemini"
  printf '# 我自己的 Codex 说明\n' > "$HOME/.codex/AGENTS.md"
  mg setup
  mkdir -p "$HOME/.agents/skills/other" && ln -s /tmp "$HOME/.claude/skills/not-ours"
  run mg uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.agents/skills/marginalia-task" ] && [ ! -e "$HOME/.claude/skills/marginalia-task" ]
  [ ! -e "$HOME/.local/bin/marginalia" ]
  [ "$(cat "$HOME/.codex/AGENTS.md")" = "# 我自己的 Codex 说明" ]
  [ ! -e "$HOME/.gemini/GEMINI.md" ]
  [ -d "$HOME/.agents/skills/other" ] && [ -L "$HOME/.claude/skills/not-ours" ]
}
