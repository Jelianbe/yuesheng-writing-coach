#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""退役档案校验器（★ 2026-10-05 层 2 单轨收口批：由「生成器」降级为「校验器」）。

真源：lib/services/syndrome_retirement.dart（50 条档案，纯文档）

─── 变更历史（三份产物 → 只剩一份留档）───

原生成器产出三份运行时产物：
  ① `syndrome_registry.dart` 的 `kSyndromeMergeMap` 段 —— 读路径归一真源
     ⇒ **已退役**：`kSyndromeMergeMap` 与 `effectiveSyndromeId` 整张删除
       （单轨 ID：号码一旦分配便永不复用 ⇒ 不再需要「读到旧号该归一到哪」）
  ② `migration_v46.dart` 的 `_legacyToCanonical` 段 —— v46 迁移改存量行
     ⇒ **已退役**：v46 迁移永不执行（它含 recycled 3 条，单轨下执行会把
       撞文同质化症的历史数据静默改成「对话疲劳症」）
     ⇒ 但该表**文件仍保留在盘上**作为历史留档，故本脚本仍校验它
  ③ 护栏豁免集合（3 个测试文件各写一遍）
     ⇒ **已改为空集**（单轨下无「合法 legacy 编号」；豁免等于把缺陷藏起来）

⇒ 现在**唯一**的机器校验对象是 ②（留档表与真源同步）。
   ①③ 的校验已由**单测**接管：
   - `test/services/syndrome_retirement_ledger_test.dart` 断言档案自身完整性
   - `test/services/syndrome_id_pattern_test.dart` 断言编号识别的生产防线在位

用法：
  python tool/gen_syndrome_retirement.py --check    # 校验（rc=1 表示漂移）
  python tool/gen_syndrome_retirement.py            # 重生成（就地改写 v46 留档表）

⚠️ 为什么留 `--check` 而不干脆删掉脚本：
   退役档案 50 条是「某个号历史上是什么」的唯一完整记录。它已无运行时消费，
   但**漂移**仍值得拦 —— 有人手改真源忘了同步留档表时 `--check` 会响。
   成本是 1 个脚本，收益是「历史记录不会悄悄失真」。
"""
from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'lib', 'services', 'syndrome_retirement.dart')
V46 = os.path.join(ROOT, 'lib', 'data', 'database', 'migration_v46.dart')

# 产物段的定界锚点（改动时必须同步改这里，否则 --check 会误判）
V46_BEGIN = "const Map<String, String> _legacyToCanonical = {"
V46_END = "\n};"

# ★ 退役前用来排除 merge map 的类别。保留常量是因为 `render_flat_map`
#   的注释要显式点出「含 recycled N 条」—— 而那三条正是 v46 必须退役的
#   根源，注释必须继续把它写在明面上，不能随merge map 一起消失。
MERGE_MAP_EXCLUDE = {'recycled'}


def read(path: str) -> str:
    # 本仓源文件是 LF（实测），但仍不归一化行尾——避免掩盖真实差异。
    with io.open(path, 'r', encoding='utf-8', newline='') as f:
        return f.read()


def parse_archive() -> list[tuple[str, str | None, str, str]]:
    """从真源 Dart 文件解析档案条目，返回 (oldId, oldName|None, target, kind)。

    ⚠️ **必须容忍 `dart format` 的折行**（本条是实测踩出来的坑）：
    旧名带括号补充说明的条目（`P004` / `P009`）行长远超 80 列，
    `dart format` 会把它们折成多行：

        SyndromeRetirement('P004', '信息倾泻症（含原 P001 世界观膨胀子类型）',
            'P002', RetirementKind.renumber),

    若正则按「单行」匹配 ⇒ 这两条会被**静默丢掉**（解析数 50 → 48），
    而产物里它们还在 ⇒ `--check` 只报「漂移」，看不出真因。
    ⇒ 这里先做「归一化空白」再匹配，**并且断言条数**（见下方guards）。
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


def render_flat_map(rows) -> str:
    recycled = sum(1 for r in rows if r[3] in MERGE_MAP_EXCLUDE)
    out = [V46_BEGIN,
           '  // ⚠️ 本段由 tool/gen_syndrome_retirement.py 生成，请勿手改。',
           '  // 真源 = lib/services/syndrome_retirement.dart（kSyndromeRetirement）',
           '  // ⚠️ 本表仅供**历史留档** —— v46 迁移已退役、永不执行。',
           '  // 全量 %d 条，含 recycled %d 条 —— 而这 %d 条正是v46 必须退役的原因：'
           % (len(rows), recycled, recycled),
           '  //   单跳语义会把存量库里任何 P035/P036/P037 行改写成旧实体，而那三个号',
           '  //   如今已是现行实体（撞文同质化症 / 细节失真症 / 故事核缺失症）。']
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
    label = '_legacyToCanonical'
    expect = render_flat_map(rows)

    if check:
        cur = read(V46)
        i = cur.find(V46_BEGIN)
        j = cur.find(V46_END, i + len(V46_BEGIN)) if i >= 0 else -1
        actual = cur[i:j + len(V46_END)] if (i >= 0 and j >= 0) else ''
        if actual != expect:
            print('[FAIL] 留档表与真源漂移：%s' % label)
            print('       修复：python tool/gen_syndrome_retirement.py')
            return 1
        print('[OK] 退役档案真源与 v46 留档表同步（%d 条档案）' % len(rows))
        print('     注：另两份产物（merge map / 护栏豁免集）已随单轨收口退役，')
        print('         其校验改由 test/services/syndrome_retirement_ledger_test.dart 承担。')
        return 0

    cur = read(V46)
    if expect in cur:
        print('[SKIP] %s 已是最新' % label)
        return 0
    with io.open(V46, 'w', encoding='utf-8', newline='') as f:
        f.write(replace_segment(cur, V46_BEGIN, V46_END, expect, label))
    print('[WRITE] %s ← %s' % (label, os.path.relpath(V46, ROOT)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
