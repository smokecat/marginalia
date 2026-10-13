"""marginalia 的文本/JSON 辅助操作，由 bin/marginalia 调用。

放在 Python 里是为了避开 GNU 与 BSD 工具（sed、readlink、realpath）的差异。
兼容 Python 3.8+，只用标准库。
"""

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
