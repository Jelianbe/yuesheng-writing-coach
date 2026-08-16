#!/usr/bin/env python3
# 通用 Flutter 大 State 类「逐字拆分」脚本（part of + 私有扩展）
#
# 适用：把膨胀的 ConsumerState 类按职责物理拆成多个 part 文件，零行为变更。
# 套路：宿主留字段/生命周期/build + 加 part 声明；每个方法整段移到
#       `// ignore_for_file` + `part of` + `extension _Xxx on _HostState` 的 part 文件。
#
# 用法：
#   1. 修改下方 CONFIG（SRC / HOST_FILE / HOST_STATE / PARTS / EXT_MAP）。
#   2. 跑：`python extract_state_parts.py`（Windows 上 Python 用 `D:/...` 路径，勿用 `/d/`）。
#   3. 跑闸门：`dart analyze lib`（或 `flutter test`，带 FLUTTER_SKIP_UPDATE_CHECK=true）。
#
# 经验（见 SKILL.md）：
#   - EXT_MAP 的扩展名：若被迁方法是**公开且被其他文件调用**，必须用**公开 UpperCamelCase**
#     （如 `ChatServiceDiagnosis`），否则外部报 `isn't defined`；纯库内私有方法用 `_Xxx` 即可。
#   - 顶部 `// ignore_for_file: invalid_use_of_protected_member` 仅 State 类需要（扩展调
#     setState/context/ref 误报）；纯 Service 类可删掉那行。
#   - `static` 方法不能进 extension（extension 无 static 成员），留宿主或提成顶层函数。
#   - 路径用 `D:/...`（Windows），勿用 `/d/`。
#
# 安全前提：目标方法体内**字符串**不含裸 `{}`（Dart 的 map/集合字面量 `{}`
#           由括号匹配正确配对，没有问题；只有写在 '...' 字符串里的花括号会干扰）。
#           本项目所有 State handler 均满足，可放心使用。

import re

CONFIG = {
    # 源宿主文件（绝对路径，Windows 用 D:/ 形式）
    "SRC": r"D:/teacher/yuesheng-flutter/lib/widgets/CHANGE_ME_page.dart",
    # part of 引用的宿主文件名（相对同目录）
    "HOST_FILE": "CHANGE_ME_page.dart",
    # 宿主私有 State 类名（扩展的 on 目标）
    "HOST_STATE": "_CHANGE_MEState",
    # 输出目录（与 SRC 同目录）
    "OUT": r"D:/teacher/yuesheng-flutter/lib/widgets",
    # 每个 part 文件 -> 要迁移的方法名列表（顺序随意，扩展内顺序不影响）
    "PARTS": {
        # "my_feature.dart": ["_handleFeatureA", "_handleFeatureB"],
    },
    # 每个 part 文件 -> 扩展名（随便起，建议 _<Host><Feature>）
    "EXT_MAP": {
        # "my_feature.dart": "_MyFeature",
    },
}


def find_method(lines, name):
    """按 '  返回类型 方法名(' 2 空格签名行定位（避开深层缩进的调用语句）。"""
    pat = re.compile(r'^  \S.*?\b' + re.escape(name) + r'\s*\(')
    for i, ln in enumerate(lines):
        if pat.match(ln):
            return i
    raise RuntimeError("method not found: " + name)


def block_end(lines, start):
    """从签名行找到方法体结束行（括号匹配）。箭头单行 => 返回当前行。"""
    if '=>' in lines[start] and not lines[start].rstrip().endswith('{'):
        return start
    depth = 0
    started = False
    for i in range(start, len(lines)):
        for ch in lines[i]:
            if ch == '{':
                depth += 1
                started = True
            elif ch == '}':
                depth -= 1
        if started and depth == 0:
            return i
    raise RuntimeError("unbalanced block at " + str(start))


def main():
    SRC = CONFIG["SRC"]
    OUT = CONFIG["OUT"]
    HOST_FILE = CONFIG["HOST_FILE"]
    HOST_STATE = CONFIG["HOST_STATE"]
    PARTS = CONFIG["PARTS"]
    EXT_MAP = CONFIG["EXT_MAP"]

    if not PARTS or not EXT_MAP:
        raise SystemExit("请在 CONFIG.PARTS / CONFIG.EXT_MAP 里填写要拆的方法")

    with open(SRC, encoding="utf-8") as f:
        lines = f.read().split("\n")

    delete = []
    parts_content = {k: [] for k in PARTS}
    for part, names in PARTS.items():
        for name in names:
            s = find_method(lines, name)
            # 向上收集紧邻的 /// 文档注释，一并带走
            cs = s
            while cs > 0 and lines[cs - 1].lstrip().startswith('///'):
                cs -= 1
            e = block_end(lines, s)
            parts_content[part].append("\n".join(lines[cs:e + 1]))
            delete.append((cs, e))

    delete_set = set()
    for cs, e in delete:
        for r in range(cs, e + 1):
            delete_set.add(r)
    new_host = [ln for i, ln in enumerate(lines) if i not in delete_set]

    # 在最后一个 import 之后插入 part 声明（必须在所有 declaration 之前）
    insert_idx = None
    for i in range(len(new_host) - 1, -1, -1):
        if new_host[i].startswith("import "):
            insert_idx = i + 1
            break
    if insert_idx is None:
        raise RuntimeError("未在宿主找到 import 行，无法插入 part 声明")
    part_decls = "\n".join("part '%s';" % p for p in PARTS.keys())
    new_host[insert_idx:insert_idx] = [part_decls, ""]

    with open(SRC, "w", encoding="utf-8") as f:
        f.write("\n".join(new_host))

    for part, chunks in parts_content.items():
        ext = EXT_MAP[part]
        body = (
            "// ignore_for_file: invalid_use_of_protected_member\n"
            "part of '%s';\n\n" % HOST_FILE
            + "extension %s on %s {\n\n" % (ext, HOST_STATE)
        )
        body += "\n\n".join(chunks)
        body += "\n}\n"
        with open(OUT + "/" + part, "w", encoding="utf-8") as f:
            f.write(body)

    print("OK deleted_lines=%d parts=%s" % (len(delete_set), list(PARTS.keys())))


if __name__ == "__main__":
    main()
