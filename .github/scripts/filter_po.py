#!/usr/bin/env python3
"""从 po 文件中取出模板里用到的词条，按 msgid 排序输出，不带注释和行号。

用法: filter_po.py <模板 pot> <po 文件>

同步工作流用它从 lede 防火墙的翻译中取出 TurboACC 页面用到的词条，
这样只有这些词条的译文变化时才会出现在同步的差异里。
"""
import re
import sys

ENTRY = re.compile(r'(?:^msgctxt\s+((?:".*"\s*)+))?^msgid\s+((?:".*"\s*)+)^msgstr\s+((?:".*"\s*)+)', re.M)
PART = re.compile(r'"((?:[^"\\]|\\.)*)"')


def join(s):
    # 保留原有的转义，输出时原样放回引号中
    return "".join(PART.findall(s))


def entries(path):
    with open(path, encoding="utf-8") as f:
        for m in ENTRY.finditer(f.read()):
            yield (join(m.group(1)) if m.group(1) else None), join(m.group(2)), join(m.group(3))


def quote(s):
    return '"' + s + '"'


pot, po = sys.argv[1], sys.argv[2]
wanted = {msgid for _, msgid, _ in entries(pot) if msgid}
found = sorted((msgid, ctxt or "", msgstr) for ctxt, msgid, msgstr in entries(po) if msgid in wanted)
if not found:
    sys.exit(f"{po} 中没有 {pot} 用到的词条")

out = []
for msgid, ctxt, msgstr in found:
    if ctxt:
        out.append(f"msgctxt {quote(ctxt)}")
    out += [f"msgid {quote(msgid)}", f"msgstr {quote(msgstr)}", ""]
sys.stdout.write("\n".join(out))
