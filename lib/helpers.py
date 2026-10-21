"""marginalia 的文本/JSON 辅助操作，由 bin/marginalia 调用。

放在 Python 里是为了避开 GNU 与 BSD 工具（sed、readlink、realpath）的差异。
兼容 Python 3.8+，只用标准库。
"""

import hashlib
import json
import os
import re
import sys

START, END = "<!-- marginalia:start -->", "<!-- marginalia:end -->"
NOTE = "<!-- 本标记块由 marginalia 托管，重跑 marginalia init/setup 会替换块内内容；自定义内容写在块外 -->"
FRONTMATTER = re.compile(r"---\n(.*?)\n---\n", re.S)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def block_span(text):
    """返回托管块在 text 中的 (start, end)，没有则返回 None。"""
    i, j = text.find(START), text.find(END)
    if i == -1 or j == -1 or j < i:
        return None
    return i, j + len(END)


def upsert_block(path, body):
    """写入或替换文件中的托管块，块外内容不动。打印 CREATED / APPENDED / UPDATED / SKIPPED。"""
    block = "\n".join([START, NOTE, body.strip("\n"), END])
    if not os.path.exists(path):
        write(path, block + "\n")
        return "CREATED"
    text = read(path)
    span = block_span(text)
    if span is None:
        write(path, text.rstrip("\n") + ("\n\n" if text.strip() else "") + block + "\n")
        return "APPENDED"
    if text[span[0]:span[1]] == block:
        return "SKIPPED"
    write(path, text[:span[0]] + block + text[span[1]:])
    return "UPDATED"


def remove_block(path):
    """删除托管块；文件因此变空时删除文件。打印 REMOVED / DELETED / SKIPPED。"""
    if not os.path.exists(path):
        return "SKIPPED"
    text = read(path)
    span = block_span(text)
    if span is None:
        return "SKIPPED"
    rest = (text[:span[0]].rstrip("\n") + "\n\n" + text[span[1]:].lstrip("\n")).strip("\n")
    if not rest.strip():
        os.remove(path)
        return "DELETED"
    write(path, rest + "\n")
    return "REMOVED"


def fm_get(path, key):
    m = FRONTMATTER.match(read(path))
    if m:
        for line in m.group(1).split("\n"):
            if line.startswith(key + ":"):
                return line[len(key) + 1:].strip()
    return ""


def fm_set(path, key, value):
    text = read(path)
    m = FRONTMATTER.match(text)
    if not m:
        sys.exit("marginalia: %s 没有 frontmatter" % path)
    lines = m.group(1).split("\n")
    for i, line in enumerate(lines):
        if line.startswith(key + ":"):
            lines[i] = "%s: %s" % (key, value)
            break
    else:
        lines.append("%s: %s" % (key, value))
    write(path, "---\n" + "\n".join(lines) + "\n---\n" + text[m.end():])
    return ""


def section_field(path, label):
    """读取任务 README 中 `- **<label>**：值` 一行的值。"""
    m = re.search(r"^- \*\*%s\*\*[：:][ \t]*(.*)$" % re.escape(label), read(path), re.M)
    return m.group(1).strip() if m else ""


RESUME_FIELDS = (("state", "当前状态"), ("blocker", "卡点"), ("next", "下一步"), ("files", "关键文件"))


def front_matter(text):
    m = FRONTMATTER.match(text)
    out = {}
    if m:
        for line in m.group(1).split("\n"):
            key, sep, value = line.partition(":")
            if sep:
                out[key.strip()] = value.strip()
    return out


def section(text, heading):
    """`## <heading>` 小节的正文（到下一个二级标题为止），去掉 HTML 注释。"""
    m = re.search(r"^## %s[ \t]*\n(.*?)(?=^## |\Z)" % re.escape(heading), text, re.M | re.S)
    if not m:
        return ""
    return re.sub(r"<!--.*?-->", "", m.group(1), flags=re.S).strip()


def field(text, label):
    m = re.search(r"^- \*\*%s\*\*[：:][ \t]*(.*)$" % re.escape(label), text, re.M)
    value = m.group(1).strip() if m else ""
    return "" if value.startswith("<!--") else value


def task_info(local, path, detail=False):
    text = read(path)
    fm = front_matter(text)
    slug = os.path.basename(os.path.dirname(path))
    title = re.search(r"^# (.+)$", text, re.M)
    info = {
        "slug": slug,
        "title": title.group(1).strip() if title else slug,
        "status": fm.get("status", ""),
        "created": fm.get("created", ""),
        "updated": fm.get("updated", ""),
        "archived": os.path.basename(os.path.dirname(os.path.dirname(path))) == "archived",
        "path": os.path.relpath(path, os.path.dirname(local)),
        "resume": dict((key, field(text, label)) for key, label in RESUME_FIELDS),
    }
    if fm.get("result"):
        info["result"] = fm["result"]
    if fm.get("archived"):
        info["archivedAt"] = fm["archived"]
    if detail:
        todo = section(text, "待办")
        info["goal"] = section(text, "目标")
        info["todo"] = {
            "done": len(re.findall(r"^- \[[xX]\]", todo, re.M)),
            "total": len(re.findall(r"^- \[[ xX]\]", todo, re.M)),
        }
        info["resumeText"] = section(text, "接续指引")
    return info


def store_info(local):
    real = os.path.realpath(local)
    return {"root": real, "id": hashlib.sha256(real.encode("utf-8")).hexdigest()[:12]}


def tasks_json(local, with_archived="0"):
    """`task list --json`：未归档任务（with_archived=1 时含已归档），坏文件进 errors 不中断。"""
    tasks, errors = [], []
    dirs = [os.path.join(local, "tasks")]
    if with_archived == "1":
        dirs.append(os.path.join(local, "tasks", "archived"))
    for base in dirs:
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if name == "archived":
                continue
            path = os.path.join(base, name, "README.md")
            if not os.path.isfile(path):
                continue
            try:
                if FRONTMATTER.match(read(path)) is None:
                    errors.append({"slug": name, "path": os.path.relpath(path, os.path.dirname(local)), "error": "缺少 frontmatter"})
                    continue
                tasks.append(task_info(local, path))
            except (OSError, UnicodeDecodeError) as exc:
                errors.append({"slug": name, "path": os.path.relpath(path, os.path.dirname(local)), "error": str(exc)})
    archived_dir = os.path.join(local, "tasks", "archived")
    archived = len([n for n in os.listdir(archived_dir) if os.path.isdir(os.path.join(archived_dir, n))]) if os.path.isdir(archived_dir) else 0
    return json.dumps({"v": 1, "store": store_info(local), "tasks": tasks, "archivedCount": archived, "errors": errors}, ensure_ascii=False)


def task_json(local, path):
    return json.dumps({"v": 1, "store": store_info(local), "task": task_info(local, path, detail=True)}, ensure_ascii=False)


def render(template, dest, *pairs):
    """把模板中的 {{KEY}} 替换为值后写到 dest。pairs 形如 KEY=VALUE。"""
    text = read(template)
    for pair in pairs:
        key, _, value = pair.partition("=")
        text = text.replace("{{%s}}" % key, value)
    write(dest, text)
    return ""


def set_memory_dir(path, want):
    """在 settings.local.json 中设置 autoMemoryDirectory，保留其他字段。"""
    data = {}
    if os.path.exists(path):
        try:
            data = json.loads(read(path) or "{}")
        except ValueError:
            return "CONFLICT 无法解析，未修改"
        if not isinstance(data, dict):
            return "CONFLICT 顶层不是对象，未修改"
    cur = data.get("autoMemoryDirectory")
    if cur == want:
        return "SKIPPED"
    if cur and not cur.rstrip("/").endswith("/.local/memory"):
        return "CONFLICT 已指向 %s，未修改" % cur
    data["autoMemoryDirectory"] = want
    write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return "FIXED 路径已更新" if cur else "CREATED"


COMMANDS = {
    "upsert-block": upsert_block,
    "remove-block": remove_block,
    "fm-get": fm_get,
    "fm-set": fm_set,
    "section-field": section_field,
    "tasks-json": tasks_json,
    "task-json": task_json,
    "render": render,
    "set-memory-dir": set_memory_dir,
    "realpath": os.path.realpath,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        sys.exit("usage: helpers.py {%s} ..." % ",".join(sorted(COMMANDS)))
    out = COMMANDS[sys.argv[1]](*sys.argv[2:])
    if out:
        print(out)
