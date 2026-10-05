#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成器：由退役档案真源生成三份产物。

真源：lib/services/syndrome_retirement.dart（唯一手写处）
产物：
  ① lib/services/syndrome_registry.dart 的 kSyndromeMergeMap 段
     —— 读路径归一真源；**排除 recycled**（槽位待复用，新号不能被旧映射改写）
  ② lib/data/database/migration_v46.dart 的 _legacyToCanonical 段
     —— 迁移改存量行；**全量 50 条**（含 recycled：存量库里真有这些旧号）
  ③ 护栏豁免集合（syndrome_reference_integrity_test.dart / four_libraries_…）
     —— 合法 legacy 编号全集，同样是全量

用法：
  python tool/gen_syndrome_retirement.py            # 重生成（就地改写三处）
  python tool/gen_syndrome_retirement.py --check    # 只验产物是否与真源同步，rc=1 表示漂移

⚠️ 为什么产物 checked-in 而不是构建时生成：
   门禁基线 json（r019_baseline.json 等）都是 checked-in 的，同惯例。
   --check 让「产物漂移」可被门禁/单测捕获，而不必真的跑生成。
"""
from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'lib', 'services', 'syndrome_retirement.dart')
REG = os.path.join(ROOT, 'lib', 'services', 'syndrome_registry.dart')
V46 = os.path.join(ROOT, 'lib', 'data', 'database', 'migration_v46.dart')

# 产物段的定界锚点（改动时必须同步改这里，否则 --check 会误判）
REG_BEGIN = "const Map<String, String> kSyndromeMergeMap = {"
REG_END = "\n};"
V46_BEGIN = "const Map<String, String> _legacyToCanonical = {"
V46_END = "\n};"

# excluded kinds → 不进 merge map（但仍进 v46 平铺表与豁免集合）
MERGE_MAP_EXCLUDE = {'recycled'}


def read(path: str) -> str:
    # 本仓源文件是 LF（实测），但仍不归一化行尾——避免掩盖真实差异。
    with io.open(path, 'r', encoding='utf-8', newline='') as f:
        return f.read()


def parse_archive() -> list[tuple[str, str, str, str]]:
    """从真源 Dart 文件解析档案条目，返回 (oldId, oldName|None, target, kind)。

    ⚠️ **必须容忍 `dart format` 的折行**（本条是实测踩出来的坑）：
    旧名带括号补充说明的条目（`P004` / `P009`）行长远超 80 列，
    `dart format` 会把它们折成多行：

        SyndromeRetirement('P004', '信息倾泻症（含原 P001 世界观膨胀子类型）', 'P002',
            RetirementKind.renumber),

    若正则按「单行」匹配 ⇒ 这两条会被**静默丢掉**（解析数 50 → 48），
    而产物里它们还在 ⇒ `--check` 只报「漂移」，看不出真因。
    ⇒ 这里先做「归一化空白」再匹配，**并且断言条数**（见下方 guards）。
    """
    src = read(SRC)
    body = re.search(r'kSyndromeRetirement\s*=\s*\[(.*?)\n\];', src, re.S)
    if not body:
        raise SystemExit('未在 %s 找到 kSyndromeRetirement 列表' % SRC)
    # 折行归一：把跨行的一条记录拼回一行（record 内部无嵌套方括号，安全）
    flat = re.sub(r'\s*\n\s*', ' ', body.group(1))
    rows = []
    pat = re.compile(
        r"SyndromeRetirement\(\s*'([^']+)'\s*,\s*(null|'[^']*')\s*,\s*'([^']+)'\s*,"
        r"\s*RetirementKind\.(\w+)\s*\)")
    for m in pat.finditer(flat):
        sid, name, tgt, kind = m.groups()
        name = None if name == 'null' else name[1:-1]
        rows.append((sid, name, tgt, kind))
    if not rows:
        raise SystemExit('真源解析出 0 条 —— 正则与源文件不匹配？')
    # 守卫：解析数必须等于字面 `SyndromeRetirement(` 出现次数。
    # ⚠️ 这道守卫是「静默丢条目」的唯一拦截点 —— 折行容忍一旦失效，
    #   少了断言就会变成「产物少两条、测试才发现」的晚失败。
    literal = len(re.findall(r'SyndromeRetirement\(', body.group(1)))
    if literal != len(rows):
        raise SystemExit(
            '解析条数(%d) != 源码字面条数(%d) —— 正则漏匹配（多半是折行形态变了）。\n'
            '  修法：调整 parse_archive 的折行归一化，不要改数据。' % (len(rows), literal))
    return rows


def render_merge_map(rows) -> str:
    out = [REG_BEGIN, '  // ⚠️ 本段由 tool/gen_syndrome_retirement.py 生成，请勿手改。',
           '  // 真源 = lib/services/syndrome_retirement.dart（kSyndromeRetirement）',
           '  // 含 %d 条；**排除 recycled %d 条**（槽位待复用为新症候）'
           % (len(rows), sum(1 for r in rows if r[3] in MERGE_MAP_EXCLUDE))]
    for sid, name, tgt, kind in rows:
        if kind in MERGE_MAP_EXCLUDE:
            continue
        # ⚠️ 注释**只放 ID + 类别**，不复制旧名：旧名普遍超长，
        #   复制过来会让本行超 80 列 ⇒ dart format 折行 ⇒ 产物与生成器
        #   的字符串永远对不上（实测踩过：P004/P009）。
        #   旧名要查 → 看真源 syndrome_retirement.dart。
        out.append("  '%s': '%s', // %s" % (sid, tgt, kind))
    return '\n'.join(out) + REG_END


def render_flat_map(rows) -> str:
    out = [V46_BEGIN,
           '  // ⚠️ 本段由 tool/gen_syndrome_retirement.py 生成，请勿手改。',
           '  // 真源 = lib/services/syndrome_retirement.dart（kSyndromeRetirement）',
           '  // 全量 %d 条（含 recycled %d 条：存量库里仍有这些旧号的历史行）'
           % (len(rows), sum(1 for r in rows if r[3] in MERGE_MAP_EXCLUDE))]
    for sid, name, tgt, kind in rows:
        out.append("  '%s': '%s'," % (sid, tgt))
    return '\n'.join(out) + V46_END


def replace_segment(text: str, begin: str, end: str, new_seg: str, label: str) -> str:
    i = text.find(begin)
    if i < 0:
        raise SystemExit('未找到段首锚点 %s（%s）' % (begin, label))
    j = text.find(end, i + len(begin))
    if j < 0:
        raise SystemExit('未找到段尾锚点 %s（%s）' % (end, label))
    return text[:i] + new_seg + text[j + len(end):]


def main(argv) -> int:
    check = '--check' in argv
    rows = parse_archive()

    targets = [
        (REG, REG_BEGIN, REG_END, render_merge_map(rows), 'kSyndromeMergeMap'),
        (V46, V46_BEGIN, V46_END, render_flat_map(rows), '_legacyToCanonical'),
    ]

    if check:
        drift = []
        for path, begin, end, expect, label in targets:
            cur = read(path)
            i = cur.find(begin)
            j = cur.find(end, i + len(begin)) if i >= 0 else -1
            actual = cur[i:j + len(end)] if (i >= 0 and j >= 0) else ''
            if actual != expect:
                drift.append(label)
        if drift:
            print('[FAIL] 产物与真源漂移：%s' % '、'.join(drift))
            print('       修复：python tool/gen_syndrome_retirement.py')
            return 1
        print('[OK] 三份产物与退役档案真源同步（%d 条档案）' % len(rows))
        return 0

    for path, begin, end, expect, label in targets:
        cur = read(path)
        if expect in cur:
            print('[SKIP] %s 已是最新' % label)
            continue
        with io.open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(replace_segment(cur, begin, end, expect, label))
        print('[WRITE] %s ← %s' % (label, os.path.relpath(path, ROOT)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
