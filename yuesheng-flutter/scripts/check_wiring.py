#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""W1 · DB 列「只写不读 / 全无消费者」守卫 —— 全链路活性审查（T-20261018-01）的机器执行点。

背景（2026-10-18 审查批实测）
--------------------------------
活性审查第一刀确证 6 个死列：`ai_accounts.isEnabled`（建列后零写入零过滤零 UI）
与 5 个只写不读列（attitudePreference / decidedAt / diagnosisSummary /
errorMessage / sourceCredibility）。根因是系统性盲区：全部既有护栏验证
「代码跑起来做什么」，没有护栏验证「生产有没有真的走到它」——
死代码能过全部门禁（门禁直接调它），**coverage ≠ liveness**。

★ 本脚本的定性
--------------
**约定层守卫，不是门禁**（与 check_extension_shape.py 同款定性）。
WARN 起步：收尾时跑一次，报红即须当场处置（登记豁免 or 补读侧），
不阻断收尾。升阻断须用户裁定。

判据
----
- **W1**：drift schema 列（排除 .g.dart 自身）在 lib/ 内零字面命中 ⇒ dead 候选。
- **W2**：命中 ≤ `--low-threshold`（缺省 2）且全部为写入模式 ⇒ 只写不读候选。
- **G1**：基线登记的列在 lib 内已不存在（列被删）⇒ 报红（豁免表腐烂检测）。
- **G2**：基线豁免必带 `reason`（无 reason ⇒ exit 2）。
- **G3**：基线外发现新死列 ⇒ 报红（止血模式：只报新增，基线内豁免）。

★ 已知局限（勿删，方法论实测教训）
------------------------------------
① grep 假阴性两例实证（focusCandidates / evidence_count）：typed 访问与
   同文件序列化往返都会让「字面 key」扫描漏判。本守卫宁可漏报不误报——
   所有命中均需人工精核后才进基线；基线条目必须有精核记录。
② 动态分发（字符串拼 key）不可见 ⇒ 本守卫只做增量防复发（新列必须
   带消费者），不做历史存量清理。
③ 「读」的判定含 widget/provider 的 `.field` 访问（typed），W2 的
   「写入模式」= `field: Value(...)` / `field: params.x` 赋值形态。

用法
----
    python scripts/check_wiring.py --baseline tool/wiring_baseline.json
    python scripts/check_wiring.py                    # 全量报告
    python scripts/check_wiring.py --json tool/wiring_baseline.json --force
                                                        # 重生成（勿与 --baseline 同用）

⚠️ 与既有基线同源纪律：**拿来「检查」是对的，拿来「重生成」就是自杀。**

退出码
------
    0 = 通过（或止血模式下无新增）
    1 = 有新增死列 / 基线腐烂
    2 = 环境错误（schema 缺失 / 基线结构非法 / 参数冲突）
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

SCHEMA = os.path.join('lib', 'data', 'database', 'tables.dart')
DEFAULT_BASELINE = os.path.join('tool', 'wiring_baseline.json')
LOW_THRESHOLD = 2

_COL_RE = re.compile(
    r'\b(?:Text|Int|Real|Bool|DateTime|BigInt)Column\s+get\s+(\w+)\s*=>')
_WRITE_RE = re.compile(
    r'%s\s*:\s*(Value|const|params|input|absent)' )


def _load_lib_sources(lib_root='lib'):
    """全 lib 源（排除生成文件与 schema 自身）。"""
    out = {}
    for root, _, files in os.walk(lib_root):
        for f in files:
            if not f.endswith('.dart') or f.endswith('.g.dart'):
                continue
            if f == 'tables.dart' and root.endswith(os.path.join('data', 'database')):
                continue
            p = os.path.join(root, f)
            with open(p, encoding='utf-8', errors='replace') as fh:
                out[p] = fh.read()
    return out


def _scan(sources, col):
    """返回 (hits, write_like)。hits = 全字面命中；write_like = 写入形态命中。"""
    word = re.compile(r'\b' + re.escape(col) + r'\b')
    wr = re.compile(r'\b' + re.escape(col) + r'\s*:\s*(?:Value\b|const\b|params\.|input\.)')
    hits, writes = [], []
    for p, src in sources.items():
        rel = os.path.relpath(p, 'lib').replace(os.sep, '/')
        for m in word.finditer(src):
            ln = src[:m.start()].count('\n') + 1
            line = src.split('\n')[ln - 1]
            hits.append('%s:%d' % (rel, ln))
            if wr.search(line):
                writes.append('%s:%d' % (rel, ln))
    return hits, writes


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument('--baseline', default=None)
    ap.add_argument('--json', default=None)
    ap.add_argument('--force', action='store_true')
    ap.add_argument('--low-threshold', type=int, default=LOW_THRESHOLD)
    ap.add_argument('--lib', default='lib')
    args = ap.parse_args()

    if args.json and args.baseline:
        print('FAIL 参数冲突：--json 与 --baseline 不得同用（重生成 vs 检查）')
        return 2
    if not os.path.exists(SCHEMA):
        print('FAIL 找不到 schema：%s（须在 yuesheng-flutter/ 下运行）' % SCHEMA)
        return 2

    schema_src = open(SCHEMA, encoding='utf-8', errors='replace').read()
    cols = sorted(set(_COL_RE.findall(schema_src)))
    if not cols:
        print('FAIL schema 零列命中——正则或 schema 结构变化，先人工核实')
        return 2

    sources = _load_lib_sources(args.lib)
    findings = {}
    for c in cols:
        hits, writes = _scan(sources, c)
        if not hits:
            findings[c] = {'verdict': 'dead', 'hits': [], 'writes': []}
        elif len(hits) <= args.low_threshold and len(writes) == len(hits):
            findings[c] = {'verdict': 'write_only', 'hits': hits, 'writes': writes}

    # 重生成模式
    if args.json:
        if os.path.exists(args.json) and not args.force:
            print('FAIL 基线已存在（%s）；重生成须 --force' % args.json)
            return 2
        with open(args.json, 'w', encoding='utf-8') as fh:
            json.dump({'schema': 'wiring-baseline/1',
                       'note': 'DB 列活性基线；豁免必带 reason（精核记录）',
                       'columns': findings}, fh, ensure_ascii=False, indent=1)
        print('基线已生成：%s（dead=%d, write_only=%d）'
              % (args.json, sum(1 for v in findings.values() if v['verdict'] == 'dead'),
                 sum(1 for v in findings.values() if v['verdict'] == 'write_only')))
        print('⚠️ 重生成后必须逐条补 reason 并负向验证，否则豁免表会腐烂')
        return 0

    # 检查模式
    if not args.baseline or not os.path.exists(args.baseline):
        print('全量报告（无基线 = 无豁免）：')
        for c, v in sorted(findings.items()):
            print('  [%s] %s  %s' % (v['verdict'], c, v['hits'][:3]))
        print('共 dead=%d write_only=%d' % (
            sum(1 for v in findings.values() if v['verdict'] == 'dead'),
            sum(1 for v in findings.values() if v['verdict'] == 'write_only')))
        return 0

    with open(args.baseline, encoding='utf-8') as fh:
        base = json.load(fh)
    if base.get('schema') != 'wiring-baseline/1':
        print('FAIL 基线结构非法（schema 字段不符）')
        return 2

    exempt = base.get('columns', {})
    bad = 0
    # G2：豁免必带 reason
    for c, meta in exempt.items():
        if not meta.get('reason'):
            print('FAIL [G2] 豁免 %s 无 reason（豁免必带精核依据）' % c)
            bad += 1
    # G1：基线内列已不存在（列被删 / 改名 ⇒ 豁免腐烂）
    for c in exempt:
        if c not in cols:
            print('FAIL [G1] 基线豁免 %s 在 schema 已不存在——列被删/改名，豁免表腐烂，须重生成' % c)
            bad += 1
    # G3：新增死列（不在基线内的发现）
    for c, v in sorted(findings.items()):
        if c in exempt:
            continue
        print('FAIL [G3] 新增死列：%s（%s）——须补读侧或登记豁免' % (c, v['verdict']))
        bad += 1
    # 豁免列的现状复核：仍应处于 dead/write_only（若它活了，豁免该撤）
    for c in exempt:
        if c in findings and findings[c]['verdict'] != exempt[c].get('verdict'):
            print('WARN 豁免 %s 状态变化：基线=%s 实测=%s（若已修复，建议撤出基线）'
                  % (c, exempt[c].get('verdict'), findings[c]['verdict']))

    if bad:
        print('----')
        print('守卫判定：FAIL（%d 项须处置）' % bad)
        return 1
    print('守卫判定：PASS（基线 %d 列豁免有效，无新增死列）' % len(exempt))
    return 0


if __name__ == '__main__':
    sys.exit(main())
