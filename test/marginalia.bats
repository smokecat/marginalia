#!/usr/bin/env bats
# 运行：bats test/   用指定 bash 运行（如 macOS 自带的 3.2）：MARGINALIA_TEST_BASH=/bin/bash bats test/

setup() {
  REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)
  # 隔离 HOME 与 git 全局配置，测试不读写真实环境
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"  # 默认只装了 Claude Code；测 Codex / Gemini 的用例自己建配置目录
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  git config --global user.name test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false
  unset CLAUDE_CONFIG_DIR CODEX_HOME GEMINI_CLI_HOME MARGINALIA_DIR MARGINALIA_USER_CONFIG
  export MARGINALIA_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/etc/marginalia/config"
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
  [ -d "$P/.git" ] && [ -d "$P/.margin/.git" ]
}

@test "init：落地骨架、exclude、CLAUDE.local.md、memory 设置，主仓库保持干净" {
  init_repo "$P"
  run mg init "$P"
  [ "$status" -eq 0 ]
  for f in README.md .gitignore todo.md templates/task.md memory/MEMORY.md; do [ -f "$P/.margin/$f" ]; done
  for d in tasks/archived docs ops scripts out logs tmp; do [ -d "$P/.margin/$d" ]; done
  [ "$(git -C "$P/.margin" log --oneline | wc -l | tr -d ' ')" = 1 ]
  grep -qxF .margin "$P/.git/info/exclude"
  grep -qxF CLAUDE.local.md "$P/.git/info/exclude"
  grep -q "marginalia:start" "$P/CLAUDE.local.md"
  grep -qxF "@AGENTS.md" "$P/CLAUDE.local.md"       # 没有 CLAUDE.md 时兜底 import
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["autoMemoryDirectory"]==sys.argv[2]' \
    "$P/.claude/settings.local.json" "$P/.margin/memory"
  [ -z "$(git -C "$P" status --porcelain)" ]
}

@test "init：幂等，重跑没有新建也没有新 commit" {
  init_repo "$P"
  mg init "$P"
  run mg init "$P"
  [ "$status" -eq 0 ]
  lacks "[CREATED]"
  lacks "[COMMITTED]"
  [ "$(git -C "$P/.margin" log --oneline | wc -l | tr -d ' ')" = 1 ]
  [ "$(grep -c '^\.margin$' "$P/.git/info/exclude")" = 1 ]
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
  sed 's/私有工作区（.margin\/）/被改掉/' "$P/CLAUDE.local.md" > "$P/x" && mv "$P/x" "$P/CLAUDE.local.md"
  run mg init "$P"
  has "[UPDATED] CLAUDE.local.md"
  grep -q "私有工作区（.margin/）" "$P/CLAUDE.local.md"
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
  echo "本地改动" >> "$P/.margin/README.md"
  git -C "$P/.margin" commit -qam "local edit"
  run mg init "$P"
  has "[ASK] .margin/README.md"
  has "tmp/marginalia-README-"
  ls "$P/.margin/tmp/"marginalia-README-* >/dev/null
  run mg init --update-spec "$P"
  has "[UPDATED] .margin/README.md"
  has "[COMMITTED]"
  [ "$(cat "$P/.margin/README.md")" = "$(python3 "$REPO/lib/helpers.py" render "$REPO/templates/local/README.md" - DIR=.margin)" ]
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
  grep -q "trap.md" "$P/.margin/memory/MEMORY.md"
  [ -f "$P/.margin/memory/trap.md" ] && [ -f "$old/trap.md" ]
}

@test "init：worktree 要求主工作区先初始化，之后共享同一个 .margin" {
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
  [ "$(readlink "$wt/.margin")" = "$P/.margin" ]
  grep -q "\"$P/.margin/memory\"" "$wt/.claude/settings.local.json"
  [ -z "$(git -C "$wt" status --porcelain)" ]
  (cd "$wt" && mg task new from-wt >/dev/null)
  [ -f "$P/.margin/tasks/from-wt/README.md" ]
}

# ------------------------------------------------------------------ task

@test "task：项目没有 .margin 时报错" {
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
  grep -qxF '# 修复登录 & 会话 "问题" \1' "$P/.margin/tasks/fix-login/README.md"
  sed 's/^- \*\*当前状态\*\*：$/- **当前状态**：定位到 token 刷新/' "$P/.margin/tasks/fix-login/README.md" > x && mv x "$P/.margin/tasks/fix-login/README.md"

  run mg task list
  has "fix-login"
  has "定位到 token 刷新"
  has "已归档：0 个"

  run mg task status fix-login wip
  [ "$status" -ne 0 ]
  run mg task status fix-login blocked
  [ "$status" -eq 0 ]
  grep -qx "status: blocked" "$P/.margin/tasks/fix-login/README.md"

  run mg task archive fix-login
  [ "$status" -ne 0 ]
  has "--force"
  run mg task archive fix-login 修好了 token 刷新 --force
  [ "$status" -eq 0 ]
  local f="$P/.margin/tasks/archived/fix-login/README.md"
  grep -qx "result: 修好了 token 刷新" "$f"
  grep -q "^archived: " "$f"

  run mg task list
  has "没有未归档任务"
  has "已归档：1 个"
  [ -z "$(git -C "$P/.margin" status --porcelain)" ]
  [ "$(git -C "$P/.margin" log --oneline | wc -l | tr -d ' ')" = 4 ]
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

@test "task：在 .margin 目录内也能定位项目" {
  init_repo "$P"
  mg init "$P"
  cd "$P/.margin/tasks"
  run mg task list
  [ "$status" -eq 0 ]
}

@test "task：status / archive 也拒绝非法 slug（不能逃出 tasks 目录）" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mkdir -p "$P/.margin/x" && printf -- '---\nstatus: active\n---\n# x\n' > "$P/.margin/x/README.md"
  run mg task status ../x done
  [ "$status" -ne 0 ]
  has "kebab-case"
  grep -qx "status: active" "$P/.margin/x/README.md"
  run mg task archive ../x --force
  [ "$status" -ne 0 ]
  has "kebab-case"
}

@test "task：commit 只包含本次操作的路径，用户另外暂存的改动保持暂存" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  echo note >> "$P/.margin/todo.md"
  git -C "$P/.margin" add todo.md
  mg task new keep-staged
  [ "$(git -C "$P/.margin" diff --cached --name-only)" = "todo.md" ]
  ! git -C "$P/.margin" show --name-only --format= HEAD | grep -q todo.md
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
  sed 's/^- \*\*下一步\*\*：.*$/- **下一步**：跑测试/' "$P/.margin/tasks/alpha/README.md" > x && mv x "$P/.margin/tasks/alpha/README.md"
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
assert t["path"] == ".margin/tasks/alpha/README.md"
assert d["archivedCount"] == 1
PY
  run mg task list --json --archived
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); a=[t for t in d["tasks"] if t["archived"]]; assert [t["slug"] for t in a]==["beta"] and a[0]["path"]==".margin/tasks/archived/beta/README.md"' "$output"
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

@test "trine 扩展：没有 .margin 时返回空视图而不是报错" {
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
assert alpha["actions"][2]["effects"][0]["text"] == "../.margin/tasks/alpha/README.md", alpha["actions"][2]
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
  grep -qx "status: done" "$P/.margin/tasks/alpha/README.md"
  run ext action '{"op":"action","context":{},"args":{"actionId":"archive","params":{"slug":"alpha"}}}'
  [ -d "$P/.margin/tasks/archived/alpha" ]
  run ext action '{"op":"action","context":{},"args":{"actionId":"archive","params":{"slug":"alpha"}}}'
  has '"ok": true'
}

@test "trine 扩展：协商出 files.open 时每个任务可浏览目录 / 打开 README（自定义目录名、归档任务）" {
  init_repo "$P"
  mg init --dir .notes "$P"
  cd "$P"
  mg task new alpha 'Alpha 任务'
  mg task new beta
  mg task status beta done
  mg task archive beta
  mkdir -p "$P/src"
  local session='"session":{"id":"s1","links":[]},"linkedSessions":[]'
  run ext view '{"op":"view","point":"sessionPanel","context":{"cwd":"'"$P/src"'",'"$session"',"features":["files.open"]}}'
  [ "$status" -eq 0 ]
  python3 - "$output" "$P" <<'PY'
import json, os, sys
v = json.loads(sys.argv[1])["view"]
root = os.path.realpath(sys.argv[2])
items = {i["id"]: i for s in v["sections"] for i in s["items"]}
def opens(item):
    return {a["id"]: a["effects"] for a in item["actions"] if a["id"] in ("browse-dir", "open-readme")}
real = lambda p: os.path.realpath(p)
for slug, rel in (("alpha", ".notes/tasks/alpha"), ("beta", ".notes/tasks/archived/beta")):
    o = opens(items[slug])
    (d,), (f,) = o["browse-dir"], o["open-readme"]
    assert d["type"] == "files.open" and d["dir"] is True and os.path.isabs(d["path"]), d
    assert real(d["path"]) == os.path.join(root, rel), (d, rel)
    assert f["type"] == "files.open" and "dir" not in f and real(f["path"]) == os.path.join(root, rel, "README.md"), f
    assert len(items[slug]["actions"]) <= 8
PY
  # 旧 agent / 旧 web（不带 features）：没有这两个动作
  run ext view '{"op":"view","point":"sessionPanel","context":{"cwd":"'"$P"'",'"$session"'}}'
  python3 -c 'import json,sys; v=json.loads(sys.argv[1])["view"]; assert not [a for s in v["sections"] for i in s["items"] for a in i.get("actions",[]) if a["id"] in ("browse-dir","open-readme")]' "$output"
  # 工作区面板没有会话：即使带了也不给
  run ext view '{"op":"view","point":"workspacePanel","context":{"cwd":"'"$P"'","linkedSessions":[],"features":["files.open"]}}'
  python3 -c 'import json,sys; v=json.loads(sys.argv[1])["view"]; assert not [a for s in v["sections"] for i in s["items"] for a in i.get("actions",[]) if a["id"] in ("browse-dir","open-readme")]' "$output"
}

@test "trine 扩展：缺 frontmatter 的任务进「无法读取」，不静默消失" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mkdir -p "$P/.margin/tasks/broken" && echo '# 没有 frontmatter' > "$P/.margin/tasks/broken/README.md"
  run mg task list --json
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["tasks"]==[] and d["errors"][0]["slug"]=="broken", d' "$output"
  run ext view '{"op":"view","point":"workspacePanel","context":{"cwd":"'"$P"'","linkedSessions":[]}}'
  python3 -c 'import json,sys; s=json.loads(sys.argv[1])["view"]["sections"]; assert s[-1]["id"]=="errors" and s[-1]["items"][0]["title"]=="broken", s' "$output"
}

@test "trine 扩展：任务很多时按输出预算截断，不超过 trine 的 512 KB 上限" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  python3 - "$P/.margin/tasks" <<'PY'
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
  mv "$P/.margin/tasks/late" "$P/.margin/tasks/archived/late"
  run mg task archive late --force
  [ "$status" -eq 0 ]
  [ -z "$(git -C "$P/.margin" status --porcelain)" ]
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
  mkdir -p "$CODEX_HOME" "$CLAUDE_CONFIG_DIR"
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

# ------------------------------------------------------------------ 目录名配置

# 造一个旧版（目录名 .local、没有项目配置、没有 storeId）的项目
legacy_project() {
  init_repo "$P"
  git -C "$P" commit -q --allow-empty -m init
  MARGINALIA_DIR=.local mg init "$P" >/dev/null
  git -C "$P" config --local --unset marginalia.dir
  git -C "$P/.local" config --local --unset marginalia.storeId
  # 规范文件换成旧版 marginalia 实际写出的版本（known-specs 里登记过）
  cp "$REPO/test/fixtures/legacy-README.md" "$P/.local/README.md"
  git -C "$P/.local" commit -qam "legacy spec"
}

@test "config：系统 < 用户 < 环境变量 < 项目，--list 标出来源" {
  init_repo "$P"
  cd "$P"
  run mg config dir
  [ "$output" = ".margin" ]
  mkdir -p "$(dirname "$MARGINALIA_SYSTEM_CONFIG")"
  git config -f "$MARGINALIA_SYSTEM_CONFIG" marginalia.dir .sys
  [ "$(mg config dir)" = ".sys" ]
  mg config --user dir .usr
  [ "$(git config -f "$HOME/.marginalia/config" marginalia.dir)" = ".usr" ]
  [ "$(mg config dir)" = ".usr" ]
  [ "$(MARGINALIA_DIR=.env mg config dir)" = ".env" ]
  mg config --project dir .proj
  [ "$(MARGINALIA_DIR=.env mg config dir)" = ".proj" ]
  run mg config --list
  has "本项目：.proj（project）"
  has "新项目默认：.usr（user）"
  mg config --user --unset dir
  [ "$(mg config --user dir)" = "" ]
}

@test "config：拒绝不合法的目录名，设置时必须指定级别" {
  init_repo "$P"
  cd "$P"
  for bad in .git . .. a/b '' .claude 'a b'; do
    run mg config --user dir "$bad"
    [ "$status" -ne 0 ]
  done
  run mg config dir .x
  [ "$status" -ne 0 ]
  has "需要指定级别"
  mkdir -p "$HOME/.marginalia" && printf '[marginalia]\n\tdir = ../x\n' > "$HOME/.marginalia/config"
  run mg config dir
  [ "$status" -ne 0 ]
  has "目录名不合法"
}

@test "config：已有工作区时不能直接改项目配置，提示 migrate" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  run mg config --project dir .other
  [ "$status" -ne 0 ]
  has "marginalia migrate --to .other"
  [ "$(git -C "$P" config marginalia.dir)" = ".margin" ]
}

@test "init --dir：使用指定目录名并写入项目配置；之后改默认值不影响已有项目" {
  init_repo "$P"
  run mg init --dir .notes "$P"
  [ "$status" -eq 0 ]
  [ -d "$P/.notes/.git" ] && [ ! -e "$P/.margin" ]
  [ "$(git -C "$P" config marginalia.dir)" = ".notes" ]
  grep -qxF .notes "$P/.git/info/exclude"
  grep -q "私有工作区（.notes/）" "$P/CLAUDE.local.md"
  grep -q "^# .notes — 私有工作区" "$P/.notes/README.md"
  grep -q "\"$P/.notes/memory\"" "$P/.claude/settings.local.json"
  [ -z "$(git -C "$P" status --porcelain)" ]
  mg config --user dir .elsewhere
  [ "$(cd "$P/.notes/tasks" && mg config dir)" = ".notes" ]
  cd "$P"
  run mg task new still-here
  [ "$status" -eq 0 ]
  [ -f "$P/.notes/tasks/still-here/README.md" ]
  cd "$P/.notes/tasks"
  run mg task list
  has "still-here"
  run mg init "$P"
  lacks "[CREATED]"
}

@test "init --dir：已有工作区且名字不同时询问，不搬目录" {
  init_repo "$P"
  mg init "$P"
  run mg init --dir .other "$P"
  [ "$status" -eq 3 ]
  has "marginalia migrate --to .other"
  [ -d "$P/.margin" ] && [ ! -e "$P/.other" ]
}

@test "init：worktree 里沿用主工作区的目录名" {
  init_repo "$P"
  git -C "$P" commit -q --allow-empty -m init
  mg init --dir .notes "$P"
  git -C "$P" worktree add -q "$BATS_TEST_TMPDIR/wt"
  local wt
  wt=$(cd "$BATS_TEST_TMPDIR/wt" && pwd -P)
  run mg init "$wt"
  [ "$status" -eq 0 ]
  [ "$(readlink "$wt/.notes")" = "$P/.notes" ]
  [ -z "$(git -C "$wt" status --porcelain)" ]
}

@test "旧版 .local 项目：不迁移也照常工作，init 钉住 .local 并提示 migrate" {
  legacy_project
  cd "$P"
  run mg task new old-way
  [ "$status" -eq 0 ]
  [ -f "$P/.local/tasks/old-way/README.md" ]
  run mg init "$P"
  [ "$status" -eq 0 ]
  has "marginalia migrate"
  [ ! -e "$P/.margin" ]
  [ "$(git -C "$P" config marginalia.dir)" = ".local" ]
}

@test "没有工作区时 task 命令以退出码 5 结束" {
  init_repo "$P"
  cd "$P"
  run mg task list --json
  [ "$status" -eq 5 ]
  cd "$BATS_TEST_TMPDIR"
  run mg task list
  [ "$status" -eq 5 ]
}

# ------------------------------------------------------------------ migrate

@test "migrate：旧版 .local 迁到 .margin，worktree、exclude、托管块、settings、store id 都跟着改" {
  legacy_project
  echo "看 .local/docs/x.md；~/.local/bin 不算" > "$P/.local/docs/ref.md"
  git -C "$P/.local" add docs && git -C "$P/.local" commit -qm docs
  git -C "$P" worktree add -q "$BATS_TEST_TMPDIR/wt"
  local wt
  wt=$(cd "$BATS_TEST_TMPDIR/wt" && pwd -P)
  mg init "$wt" >/dev/null
  git -C "$P" config --local --unset marginalia.dir      # init 会钉住，这里还原成旧版状态
  cd "$P"
  mg task new keep-link
  local store_before
  store_before=$(mg task list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["store"]["id"])')

  run mg migrate --dry-run
  [ "$status" -eq 0 ]
  has "[PLAN] 移动 $P/.local → $P/.margin"
  has "worktree 软链"
  has "docs/ref.md"
  [ -d "$P/.local" ] && [ ! -e "$P/.margin" ]

  run mg migrate
  [ "$status" -eq 0 ]
  has "[MOVED]"
  [ ! -e "$P/.local" ] && [ -d "$P/.margin/tasks/keep-link" ]
  [ "$(git -C "$P" config marginalia.dir)" = ".margin" ]
  grep -qxF .margin "$P/.git/info/exclude"
  [ "$(grep -cxF .local "$P/.git/info/exclude")" = 0 ]
  [ ! -e "$wt/.local" ] && [ "$(readlink "$wt/.margin")" = "$P/.margin" ]
  has "[UPDATED] .margin/README.md（目录名随迁移更新）"     # 旧版规范文件没被改过，随迁移更新
  grep -q "^# .margin — 私有工作区" "$P/.margin/README.md"
  for r in "$P" "$wt"; do
    grep -q "私有工作区（.margin/）" "$r/CLAUDE.local.md"
    grep -q "\"$P/.margin/memory\"" "$r/.claude/settings.local.json"
    [ -z "$(git -C "$r" status --porcelain)" ]
  done
  has "docs/ref.md"
  [ "$(mg task list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["store"]["id"])')" = "$store_before" ]
  (cd "$wt" && mg task new from-wt >/dev/null)
  [ -f "$P/.margin/tasks/from-wt/README.md" ]

  run mg migrate
  [ "$status" -eq 0 ]
  has "无需迁移"
}

@test "migrate --to：可以改成任意名字，也能迁回去" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mg task new t1
  run mg migrate --to .notes
  [ "$status" -eq 0 ]
  has "[UPDATED] .notes/README.md（目录名随迁移更新）"
  grep -q "^# .notes — 私有工作区" "$P/.notes/README.md"
  [ -z "$(git -C "$P/.notes" status --porcelain)" ]
  [ -d "$P/.notes/tasks/t1" ] && [ ! -e "$P/.margin" ]
  grep -q "\"$P/.notes/memory\"" "$P/.claude/settings.local.json"
  run mg migrate --to .margin
  [ "$status" -eq 0 ]
  [ -d "$P/.margin/tasks/t1" ] && [ ! -e "$P/.notes" ]
  [ "$(grep -c '^\.margin$' "$P/.git/info/exclude")" = 1 ]
  [ "$(grep -cxF .notes "$P/.git/info/exclude")" = 0 ]
}

@test "migrate：目标已存在时拒绝；中途中断后重跑能继续" {
  init_repo "$P"
  mg init "$P"
  mkdir "$P/.taken"
  run mg migrate --to .taken "$P"
  [ "$status" -ne 0 ]
  has "已存在"
  [ -d "$P/.margin" ]
  # 模拟只完成了移动
  mv "$P/.margin" "$P/.moved"
  run mg migrate --to .moved "$P"
  [ "$status" -eq 0 ]
  has "上次迁移中断"
  [ "$(git -C "$P" config marginalia.dir)" = ".moved" ]
  grep -qxF .moved "$P/.git/info/exclude"
  grep -q "\"$P/.moved/memory\"" "$P/.claude/settings.local.json"
}

@test "migrate：项目没有工作区时退出码 5" {
  init_repo "$P"
  run mg migrate "$P"
  [ "$status" -eq 5 ]
}

# ------------------------------------------------------------------ agent 适配器

jq_py() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$@"; }

@test "setup：为 Codex / Gemini 写 SessionStart hook，保留已有配置，幂等；uninstall 恢复原样" {
  mkdir -p "$HOME/.codex" "$HOME/.gemini"
  printf '{"theme":"x","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"mine"}]}]}}\n' > "$HOME/.gemini/settings.json"
  run mg setup
  [ "$status" -eq 0 ]
  has "hooks.json SessionStart hook"
  [ "$(jq_py "$HOME/.codex/hooks.json" 'd["hooks"]["SessionStart"][0]["hooks"][0]["command"]')" = "$HOME/.local/bin/marginalia hook session-start codex" ]
  [ "$(jq_py "$HOME/.codex/hooks.json" 'd["hooks"]["SessionStart"][0]["hooks"][0]["timeout"]')" = 10 ]
  [ "$(jq_py "$HOME/.gemini/settings.json" 'd["theme"]')" = x ]
  [ "$(jq_py "$HOME/.gemini/settings.json" 'len(d["hooks"]["SessionStart"])')" = 2 ]
  [ "$(jq_py "$HOME/.gemini/settings.json" 'd["hooks"]["SessionStart"][1]["hooks"][0]["timeout"]')" = 10000 ]
  run mg setup
  lacks "[CREATED]"
  lacks "[UPDATED]"
  run mg uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.codex/hooks.json" ]
  [ "$(jq_py "$HOME/.gemini/settings.json" 'd["hooks"]["SessionStart"][0]["hooks"][0]["command"]')" = mine ]
  [ "$(jq_py "$HOME/.gemini/settings.json" 'len(d["hooks"]["SessionStart"])')" = 1 ]
}

@test "setup：hook 配置文件无法解析时报冲突，不改动" {
  mkdir -p "$HOME/.gemini"
  printf '{ // 注释\n}\n' > "$HOME/.gemini/settings.json"
  run mg setup
  [ "$status" -eq 0 ]
  has "[CONFLICT]"
  [ "$(cat "$HOME/.gemini/settings.json")" = "$(printf '{ // 注释\n}')" ]
}

@test "setup：多个全局入口软链到同一文件时只写一次" {
  mkdir -p "$HOME/.agents" "$HOME/.codex" "$HOME/.gemini"
  printf '# 共用说明\n' > "$HOME/.agents/AGENTS.md"
  ln -s "$HOME/.agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
  ln -s "$HOME/.agents/AGENTS.md" "$HOME/.gemini/GEMINI.md"
  run mg setup
  has "与前面的同一文件"
  [ "$(grep -c 'marginalia:start' "$HOME/.agents/AGENTS.md")" = 1 ]
  [ -L "$HOME/.codex/AGENTS.md" ] && [ -L "$HOME/.gemini/GEMINI.md" ]
}

@test "config agents：显式选择后 setup 撤掉未启用 agent 的入口，但不删共用文件里的块" {
  mkdir -p "$HOME/.agents" "$HOME/.codex" "$HOME/.gemini"
  printf '# 共用说明\n' > "$HOME/.agents/AGENTS.md"
  ln -s "$HOME/.agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
  ln -s "$HOME/.agents/AGENTS.md" "$HOME/.gemini/GEMINI.md"
  mg setup
  [ -L "$HOME/.claude/skills/marginalia-task" ]
  run mg config --user agents codex
  [ "$status" -eq 0 ]
  run mg config agents
  [ "$output" = codex ]
  run mg setup
  has "启用的 agent：codex"
  [ ! -e "$HOME/.claude/skills/marginalia-task" ]
  [ -L "$HOME/.agents/skills/marginalia-task" ]
  grep -q 'marginalia:start' "$HOME/.agents/AGENTS.md"
  [ "$(jq_py "$HOME/.gemini/settings.json" '"hooks" in d')" = False ] || [ ! -e "$HOME/.gemini/settings.json" ]
  [ -e "$HOME/.codex/hooks.json" ]
  run mg config --user agents claude,bogus
  [ "$status" -ne 0 ]
  run mg config --project agents codex
  [ "$status" -ne 0 ]
  mg config --user --unset agents
  run mg config agents
  [ "$output" = "claude codex gemini" ]
}

@test "init：Claude 未启用时不写 CLAUDE.local.md；已有托管块则继续维护" {
  init_repo "$P"
  mg config --user agents codex
  run mg init "$P"
  [ "$status" -eq 0 ]
  has "claude 未启用"
  [ ! -e "$P/CLAUDE.local.md" ] && [ ! -e "$P/.claude/settings.local.json" ]
  mg config --user --unset agents
  mg init "$P"
  [ -f "$P/CLAUDE.local.md" ]
  mg config --user agents codex
  run mg init "$P"
  lacks "claude 未启用"
  has "CLAUDE.local.md 托管块"
}

@test "Claude 托管块与 context 用同一份核心约定" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  run mg context
  [ "$status" -eq 0 ]
  has "**决策**"
  python3 - "$P/CLAUDE.local.md" "$REPO/templates/entry-core.md" <<'PY'
import sys
local, core = open(sys.argv[1]).read(), open(sys.argv[2]).read().replace("{{DIR}}", ".margin").strip()
assert core in local, "CLAUDE.local.md 里没有完整的核心约定"
PY
}

@test "context：核心约定、活跃任务（不含 done）、经验索引；没有工作区时退出码 5" {
  init_repo "$P"
  mg init "$P"
  cd "$P"
  mg task new alpha 阿尔法
  mg task new beta
  mg task status beta done
  printf '# Memory index\n- [坑](pit.md) — 某个坑\n' > .margin/memory/MEMORY.md
  run mg context
  [ "$status" -eq 0 ]
  has "# 私有工作区（.margin/）"
  has '`alpha`（active）阿尔法'
  lacks '`beta`'
  has "- [坑](pit.md) — 某个坑"
  lacks "# Memory index"
  mkdir -p "$BATS_TEST_TMPDIR/other" && init_repo "$BATS_TEST_TMPDIR/other"
  run mg context "$BATS_TEST_TMPDIR/other"
  [ "$status" -eq 5 ]
}

@test "hook session-start：按 stdin 的 cwd 输出 additionalContext；其他情况静默退出 0" {
  init_repo "$P"
  mg init "$P"
  mkdir -p "$P/sub"
  run bash -c "printf '{\"cwd\":\"%s\"}' '$P/sub' | '${MARGINALIA_TEST_BASH:-bash}' '$REPO/bin/marginalia' hook session-start codex"
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1])["hookSpecificOutput"]; assert d["hookEventName"]=="SessionStart"; assert "私有工作区（.margin/）" in d["additionalContext"]' "$output"
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run bash -c "printf '{\"cwd\":\"%s\"}' '$BATS_TEST_TMPDIR/plain' | '${MARGINALIA_TEST_BASH:-bash}' '$REPO/bin/marginalia' hook session-start gemini"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run bash -c "printf 'not json' | '${MARGINALIA_TEST_BASH:-bash}' '$REPO/bin/marginalia' hook session-start gemini"
  [ "$status" -eq 0 ]
  run bash -c "printf '{\"cwd\":\"/nonexistent\"}' | '${MARGINALIA_TEST_BASH:-bash}' '$REPO/bin/marginalia' hook session-start codex"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "hook 配置：和用户 handler 同组时只动自己的 handler；配置是软链时不删链接" {
  mkdir -p "$HOME/.codex" "$HOME/dotfiles"
  printf '{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"command","command":"mine"},{"type":"command","command":"old/marginalia hook session-start codex"}]},{"hooks":[{"type":"command","command":"later"}]}]}}\n' > "$HOME/.codex/hooks.json"
  mg setup
  [ "$(jq_py "$HOME/.codex/hooks.json" 'len(d["hooks"]["SessionStart"])')" = 2 ]
  [ "$(jq_py "$HOME/.codex/hooks.json" 'd["hooks"]["SessionStart"][0]["matcher"]')" = startup ]
  [ "$(jq_py "$HOME/.codex/hooks.json" 'd["hooks"]["SessionStart"][0]["hooks"][0]["command"]')" = mine ]
  [ "$(jq_py "$HOME/.codex/hooks.json" 'd["hooks"]["SessionStart"][0]["hooks"][1]["command"]')" = "$HOME/.local/bin/marginalia hook session-start codex" ]
  mg uninstall
  [ "$(jq_py "$HOME/.codex/hooks.json" 'd["hooks"]["SessionStart"][0]["hooks"]')" = "[{'type': 'command', 'command': 'mine'}]" ]
  [ "$(jq_py "$HOME/.codex/hooks.json" 'd["hooks"]["SessionStart"][1]["hooks"][0]["command"]')" = later ]
  # 软链的配置文件：只剩 marginalia 的 hook 时清空内容，链接保留
  command rm "$HOME/.codex/hooks.json"
  ln -s "$HOME/dotfiles/hooks.json" "$HOME/.codex/hooks.json"
  mg setup
  [ -L "$HOME/.codex/hooks.json" ]
  run mg uninstall
  [ -L "$HOME/.codex/hooks.json" ]
  [ "$(jq_py "$HOME/dotfiles/hooks.json" 'd')" = "{}" ]
}

@test "hook 命令里的路径带空格时会转义" {
  export HOME="$BATS_TEST_TMPDIR/my home"
  mkdir -p "$HOME/.claude" "$HOME/.codex"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  git config --global user.name test && git config --global user.email test@example.com
  mg setup
  cmd=$(jq_py "$HOME/.codex/hooks.json" 'd["hooks"]["SessionStart"][0]["hooks"][0]["command"]')
  init_repo "$P" && mg init "$P"
  run bash -c "printf '{\"cwd\":\"%s\"}' '$P' | $cmd"
  [ "$status" -eq 0 ]
  has "additionalContext"
}

@test "config agents：Claude 的 skills 目录就是共享目录时，禁用 Claude 不删共享 skills" {
  mkdir -p "$HOME/.agents/skills" "$HOME/.codex"
  command rm -rf "$HOME/.claude" && mkdir -p "$HOME/.claude"
  ln -s "$HOME/.agents/skills" "$HOME/.claude/skills"
  mg config --user agents codex
  mg setup
  [ -L "$HOME/.agents/skills/marginalia-task" ]
}

@test "GEMINI_CLI_HOME：入口、hook 和 skills 都落在它下面" {
  export GEMINI_CLI_HOME="$BATS_TEST_TMPDIR/ghome"
  mkdir -p "$GEMINI_CLI_HOME/.gemini"
  mg setup
  grep -q "marginalia:start" "$GEMINI_CLI_HOME/.gemini/GEMINI.md"
  [ -e "$GEMINI_CLI_HOME/.gemini/settings.json" ]
  [ -L "$GEMINI_CLI_HOME/.agents/skills/marginalia-task" ]
  mg uninstall
  [ ! -e "$GEMINI_CLI_HOME/.agents/skills/marginalia-task" ]
}

@test "init：agents 配置不合法时一开始就报错，不写任何文件" {
  init_repo "$P"
  mkdir -p "$HOME/.marginalia" && git config -f "$HOME/.marginalia/config" marginalia.agents bogus
  run mg init "$P"
  [ "$status" -ne 0 ]
  has "marginalia.agents 不合法"
  [ ! -e "$P/.margin" ]
}

@test "migrate：只启用 Codex 的 worktree（没有 CLAUDE.local.md）也会改链接" {
  mg config --user agents codex
  init_repo "$P"
  git -C "$P" commit -q --allow-empty -m init
  mg init --dir .notes "$P"
  git -C "$P" worktree add -q "$BATS_TEST_TMPDIR/wt" -b wt
  mg init "$BATS_TEST_TMPDIR/wt"
  [ -L "$BATS_TEST_TMPDIR/wt/.notes" ] && [ ! -e "$BATS_TEST_TMPDIR/wt/CLAUDE.local.md" ]
  run mg migrate --to .margin "$P"
  [ "$status" -eq 0 ]
  [ "$(readlink "$BATS_TEST_TMPDIR/wt/.margin")" = "$P/.margin" ]
  [ ! -e "$BATS_TEST_TMPDIR/wt/.notes" ] && [ ! -L "$BATS_TEST_TMPDIR/wt/.notes" ]
}

@test "hook：stdin 不是 JSON 且当前目录不在项目里时，stdout 和 stderr 都为空" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  cd "$BATS_TEST_TMPDIR/plain"
  run bash -c "printf 'garbage' | '${MARGINALIA_TEST_BASH:-bash}' '$REPO/bin/marginalia' hook session-start codex 2>&1"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "setup：全局入口按用户默认目录名生成" {
  mkdir -p "$HOME/.codex"
  mg config --user dir .notes
  mg setup
  grep -q '`.notes/README.md`' "$HOME/.codex/AGENTS.md"
  grep -q 'git config marginalia.dir' "$HOME/.codex/AGENTS.md"
}

@test "trine 扩展：迁移后会话关联（store id）不变，插入的路径用新目录名" {
  legacy_project
  cd "$P"
  mg task new alpha
  local store
  store=$(mg task list --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["store"]["id"])')
  mg migrate >/dev/null
  run ext badge '{"op":"badge","context":{"session":{"id":"s","links":[{"ref":"'"$store"':alpha","label":"a"}]}}}'
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["badge"]["text"]=="进行中", d' "$output"
  run ext pick '{"op":"pick","point":"composerAction","context":{"cwd":"'"$P"'"},"args":{"query":"alp"}}'
  python3 -c 'import json,sys; i=json.loads(sys.argv[1])["items"]; assert i[0]["effects"][0]["text"]==".margin/tasks/alpha/README.md", i' "$output"
}

# ------------------------------------------------------------------ 边界情况

@test "目录名校验：换行、空格、非 ASCII、大小写变体的保留名都拒绝" {
  init_repo "$P"
  cd "$P"
  for bad in $'.notes\nbad' '.Git' '.GIT' '.CLAUDE' '.Agents' '笔记' 'a b'; do
    run mg init --dir "$bad" "$P"
    [ "$status" -ne 0 ]
  done
  [ ! -e "$P/.margin" ]
}

@test "配置文件损坏时报错，不静默回退" {
  init_repo "$P"
  cd "$P"
  mkdir -p "$HOME/.marginalia" && printf '[marginalia\n\tdir = .x\n' > "$HOME/.marginalia/config"
  run mg config dir
  [ "$status" -ne 0 ]
  has "无法读取配置文件"
}

@test "普通目录不会被当成工作区（任务不会被提交进主仓库）" {
  init_repo "$P"
  mkdir -p "$P/docs" && echo x > "$P/docs/a.md"
  git -C "$P" add docs && git -C "$P" commit -qm docs
  cd "$P"
  run env MARGINALIA_DIR=docs "${MARGINALIA_TEST_BASH:-bash}" "$REPO/bin/marginalia" task new foo
  [ "$status" -eq 5 ]
  [ ! -e "$P/docs/tasks" ]
  [ "$(git -C "$P" log --oneline | wc -l | tr -d ' ')" = 1 ]
}

@test "旧版 .local 项目：同名的普通默认目录不会遮住它" {
  legacy_project
  mkdir "$P/.margin"
  cd "$P"
  run mg task list
  [ "$status" -eq 0 ]
  run mg config dir
  [ "$output" = ".local" ]
}

@test "migrate：worktree 的软链指向别处或有独立目录时整体拒绝，不动任何东西" {
  init_repo "$P"
  git -C "$P" commit -q --allow-empty -m init
  mg init "$P"
  git -C "$P" worktree add -q "$BATS_TEST_TMPDIR/wt"
  local wt
  wt=$(cd "$BATS_TEST_TMPDIR/wt" && pwd -P)
  mkdir -p "$BATS_TEST_TMPDIR/other"
  ln -s "$BATS_TEST_TMPDIR/other" "$wt/.margin"
  run mg migrate --to .notes "$P"
  [ "$status" -ne 0 ]
  has "[CONFLICT] $wt/.margin 是指向"
  [ -d "$P/.margin" ] && [ ! -e "$P/.notes" ] && [ -L "$wt/.margin" ]
  grep -qxF .margin "$P/.git/info/exclude"
  rm "$wt/.margin" && mkdir "$wt/.margin"
  run mg migrate --to .notes "$P"
  [ "$status" -ne 0 ]
  has "独立目录"
  [ -d "$P/.margin" ]
}

@test "migrate：worktree 里入口文件受版本控制时拒绝" {
  init_repo "$P"
  git -C "$P" commit -q --allow-empty -m init
  mg init "$P"
  git -C "$P" worktree add -q -b other "$BATS_TEST_TMPDIR/wt"
  local wt
  wt=$(cd "$BATS_TEST_TMPDIR/wt" && pwd -P)
  echo shared > "$wt/CLAUDE.local.md"
  git -C "$wt" add -f CLAUDE.local.md && git -C "$wt" commit -qm tracked
  run mg migrate --to .notes "$P"
  [ "$status" -ne 0 ]
  has "受版本控制"
  [ "$(cat "$wt/CLAUDE.local.md")" = shared ]
  [ -d "$P/.margin" ]
}

@test "migrate：钉住新名之后才中断（如 commit 失败），重跑能把剩余步骤做完" {
  init_repo "$P"
  mg init "$P"
  # 模拟：目录已移动、项目配置已改成新名、标记还在，但托管块和 settings 没更新
  mv "$P/.margin" "$P/.notes"
  git -C "$P" config marginalia.dir .notes
  git -C "$P" config marginalia.migrateFrom .margin
  git -C "$P" config marginalia.migrateTo .notes
  run mg migrate "$P"
  [ "$status" -eq 0 ]
  has "继续上次未完成的迁移"
  grep -q "私有工作区（.notes/）" "$P/CLAUDE.local.md"
  grep -q "\"$P/.notes/memory\"" "$P/.claude/settings.local.json"
  [ -z "$(git -C "$P" config --get marginalia.migrateFrom)" ]
  run mg migrate --to .notes "$P"
  has "无需迁移"
}

@test "migrate：旧 memory 路径带尾斜杠也能更新" {
  init_repo "$P"
  mg init --dir .notes "$P"
  printf '{"autoMemoryDirectory":"%s/.notes/memory/"}\n' "$P" > "$P/.claude/settings.local.json"
  run mg migrate --to .margin "$P"
  [ "$status" -eq 0 ]
  grep -q "\"$P/.margin/memory\"" "$P/.claude/settings.local.json"
}

@test "migrate：.claude/、.agents/ 下指进工作区的软链（local-* skill）一起改，相对链接保持相对" {
  init_repo "$P"
  git -C "$P" commit -q --allow-empty -m init
  mg init "$P"
  mkdir -p "$P/.margin/skills/local-x" "$P/.claude/skills" "$P/.agents/skills"
  ln -s ../../.margin/skills/local-x "$P/.claude/skills/local-x"
  ln -s "$P/.margin/skills/local-x" "$P/.agents/skills/local-x"
  ln -s /tmp "$P/.claude/skills/not-ours"
  git -C "$P" worktree add -q "$BATS_TEST_TMPDIR/wt"
  local wt
  wt=$(cd "$BATS_TEST_TMPDIR/wt" && pwd -P)
  mg init "$wt" >/dev/null
  mkdir -p "$wt/.claude/skills" && ln -s ../../.margin/skills/local-x "$wt/.claude/skills/local-x"
  run mg migrate --to .notes --dry-run "$P"
  has "[PLAN] 软链 .claude/skills/local-x → ../../.notes/skills/local-x"
  [ "$(readlink "$P/.claude/skills/local-x")" = ../../.margin/skills/local-x ]
  run mg migrate --to .notes "$P"
  [ "$status" -eq 0 ]
  [ "$(readlink "$P/.claude/skills/local-x")" = ../../.notes/skills/local-x ]
  [ "$(readlink "$P/.agents/skills/local-x")" = "$P/.notes/skills/local-x" ]
  [ "$(readlink "$P/.claude/skills/not-ours")" = /tmp ]
  [ "$(readlink "$wt/.claude/skills/local-x")" = ../../.notes/skills/local-x ]
  [ -d "$wt/.claude/skills/local-x/" ]
}
