# -*- coding: utf-8 -*-
"""L0-b · 判据条款分片外依赖静态审计（B0c 前半件 · 0 token）。

依据
----
立项书 L0-b（`.ai/reports/2026-10-24-诊断层重构/00-立项书-骨架.md` §三）：
  判据若依赖分片外信息（「已由后文解释」「须全文自洽」「经多卷积累」），
  在分块链上不得作为豁免。做法是**对 38 段手册做静态字符串审计**。
底表（oracle）= C 册 §4.E4（`C-测量与实验设计.md:422-447`）：
  6 个高危 ID / 24 条例外条款，四分类计数 = 类型自证 12 / 意图自证 3 /
  跨片依赖 4 / 可指认 5。逐条出处 = 手册 4/5/6 的「原例外内化」行。

本工具**只做机器可判的部分**（不假装能自动做语义四分类，那是人评的活）：
  ① 六段例外行存在且各 ID 条款数与底表一致（分母守卫 + 棘轮）；
  ② 「分片外依赖」标志词命中集与底表 4 条一致（L0-b 判据本体）；
  ③ 条款序号 ①..N 连续无缺号（新增条款必被发现）。
语义分类（类型自证/意图自证/可指认）仍归 §4.E4 人评表，不在此脚本断言范围。

失败形态（fail-closed）：
  rc=1 审计不符（条款数/序号/命中集/底表 ID 集合漂移）；
  rc=2 空分母（文件缺失、找不到例外段、条款切不出）——
       「没测到」不等于「通过」，与 check_r019.py 空分母守卫同纪律。

用法：
  python tool/check_l0b.py                        # 审计并落 outputs/gate/l0b_audit.json
  python tool/check_l0b.py --selftest            # 负向变异自检（必跑）
  python tool/check_l0b.py --files a.dart ...     # 指定手册文件（selftest 用）
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys

# ── 底表（C 册 §4.E4 实测读数，改这里 = 先改底表报告，不许就地改数字） ──
BASELINE = {
    'P019': 3,  # 卷末收官 / 高密度信息 / 经多卷积累
    'P020': 3,  # 单元剧 / 日常治愈 / 短篇完结
    'P022': 3,  # 慢热 / 单段落内部 / 高潮段执行差
    'P035': 5,  # 通用件辨识 / 刻意复古 / 短篇小品 / 须全文自洽 / 泛化三人称
    'P036': 5,  # 概括交代 / 悬疑留白 / 诗化 / 破碎感知 / 已由后文解释
    'P037': 5,  # 多线交汇 / 短篇小品 / 单元剧 / 刻意藏住 / 一人称意识流
}
BASELINE_TOTAL = 24
# 跨片依赖底表分布（E4 表「跨片依赖」列：P019=2 / P035=1 / P036=1，合计 4）
CROSS_SHARD_MARKERS = {
    '经多卷积累': 'P019',
    '卷末/全书收官章': 'P019',
    '须全文自洽': 'P035',
    '已由后文解释': 'P036',
}
BASELINE_CROSS_SHARD = {'P019': 2, 'P035': 1, 'P036': 1}
CIRCLED = '①②③④⑤⑥⑦⑧⑨'

SECTION_RE = re.compile(r'^### (P\d{3})\b')
EXCEPTION_RE = re.compile(r'以下不判.*原例外内化')
CLAUSE_RE = re.compile(r'([' + CIRCLED + r'])([^' + CIRCLED + r']*)')


def default_files(root):
    base = os.path.join(root, 'lib', 'services')
    return [
        os.path.join(base, 'syndrome_kb_content_manual_%d.dart' % n)
        for n in (4, 5, 6)
    ]


def scan(paths):
    """返回 (sections, errors)：sections = {id: {'file','line','clauses'}}。"""
    sections = {}
    errors = []
    for path in paths:
        if not os.path.isfile(path):
            errors.append('手册文件缺失: %s' % path)
            continue
        src = io.open(path, encoding='utf-8', errors='replace').read()
        current = None
        for lineno, line in enumerate(src.split('\n'), start=1):
            m = SECTION_RE.match(line)
            if m:
                current = m.group(1)
                continue
            if current is None or current not in BASELINE:
                continue
            if not EXCEPTION_RE.search(line):
                continue
            clauses = {}
            for ordinal, body in CLAUSE_RE.findall(line):
                clauses[ordinal] = body.strip(' ；。')
            sections[current] = {
                'file': os.path.basename(path),
                'line': lineno,
                'clauses': clauses,
                'raw_sha': hashlib.sha256(
                    line.encode('utf-8')).hexdigest()[:12],
            }
            current = None
    return sections, errors


def audit(sections, errors):
    """返回 (report, rc)。rc=2 空分母；rc=1 漂移；rc=0 一致。"""
    report = {
        'baseline': {'total': BASELINE_TOTAL, 'perId': BASELINE,
                     'crossShard': BASELINE_CROSS_SHARD},
        'found': {}, 'crossShardHits': [], 'violations': [],
        'denominator': {'filesScanned': 0, 'sectionsFound': 0,
                        'clausesFound': 0},
    }
    report['denominator']['filesScanned'] = len(set(
        s['file'] for s in sections.values()))
    report['denominator']['sectionsFound'] = len(sections)
    report['denominator']['clausesFound'] = sum(
        len(s['clauses']) for s in sections.values())

    missing = sorted(set(BASELINE) - set(sections))
    extra = sorted(set(sections) - set(BASELINE))
    if missing:
        report['violations'].append('例外段缺失: %s' % ','.join(missing))
    if extra:
        report['violations'].append('底表外新增例外段: %s' % ','.join(extra))
    if errors:
        report['violations'].extend(errors)

    cross = {}
    for sid in sorted(sections):
        s = sections[sid]
        clauses = s['clauses']
        report['found'][sid] = {
            'file': s['file'], 'line': s['line'],
            'clauseCount': len(clauses), 'rawSha': s['raw_sha'],
            'clauses': clauses,
        }
        if sid in BASELINE and len(clauses) != BASELINE[sid]:
            report['violations'].append(
                '%s 条款数 %d ≠ 底表 %d' % (sid, len(clauses), BASELINE[sid]))
        expected = [CIRCLED[i] for i in range(BASELINE.get(sid, 0))]
        if sid in BASELINE and list(clauses.keys()) != expected:
            report['violations'].append(
                '%s 条款序号不连续/缺号: %s' % (sid, ','.join(clauses.keys())))
        for ordinal, body in clauses.items():
            for marker, owner in CROSS_SHARD_MARKERS.items():
                if marker in body:
                    hit = '%s%s:%s' % (sid, ordinal, marker)
                    if hit not in report['crossShardHits']:
                        report['crossShardHits'].append(hit)
                    if sid != owner:
                        report['violations'].append(
                            '跨片依赖标志词出现在底表外 ID: %s' % hit)
                    cross[sid] = cross.get(sid, 0) + 1

    total = sum(len(s['clauses']) for s in sections.values())
    if total != BASELINE_TOTAL:
        report['violations'].append(
            '条款总数 %d ≠ 底表 %d' % (total, BASELINE_TOTAL))
    if cross != BASELINE_CROSS_SHARD:
        report['violations'].append(
            '跨片依赖分布 %s ≠ 底表 %s' % (cross, BASELINE_CROSS_SHARD))
    report['crossShardDistribution'] = cross

    # 空分母守卫：没测到东西不许判绿（fail-closed）
    d = report['denominator']
    if d['filesScanned'] == 0 or d['sectionsFound'] == 0 or d['clausesFound'] == 0:
        report['violations'].append('空分母（file/section/clause 计数为 0）')
        return report, 2
    return report, (1 if report['violations'] else 0)


def selftest():
    """负向变异：证明审计器真的能变红（同源判据不两侧同变异）。"""
    import tempfile
    cases = []

    def run(label, text, expect_rc, expect_keyword=''):
        with tempfile.NamedTemporaryFile(
                mode='w', suffix='.dart', encoding='utf-8',
                delete=False) as f:
            f.write(text)
            tmp = f.name
        try:
            sections, errors = scan([tmp])
            rep, rc = audit(sections, errors)
            ok = rc == expect_rc and (
                not expect_keyword or
                any(expect_keyword in v for v in rep['violations']))
            cases.append((label, rc, expect_rc, ok, rep['violations'][:2]))
        finally:
            os.unlink(tmp)

    # 构造与真源同形的 6 段（只保留工具能判的骨架：ID/序号/标志词）
    def stub(drop_marker='', drop_ordinal=False, drop_section=False):
        parts = []
        spec = {
            'P019': (3, ['卷末/全书收官章——收束', '高密度信息章',
                       '经多卷积累、文本可指']),
            'P020': (3, ['单元剧/副本流', '日常/治愈流', '短篇完结型']),
            'P022': (3, ['慢热型故事', '单段落内部', '高潮段执行差']),
            'P035': (5, ['通用件辨识', '刻意复古', '短篇小品',
                       '须全文自洽，局部不判', '泛化第三人称']),
            'P036': (5, ['概括交代背景', '悬疑刻意留白', '诗化',
                       '破碎感知', '已由后文解释的设定']),
            'P037': (5, ['多线交汇点', '短篇小品', '单元剧结构',
                       '刻意藏住', '第一人称意识流']),
        }
        for sid, (_, bodies) in spec.items():
            if drop_section and sid == 'P037':
                continue
            line = ''.join(
                '%s%s；' % (CIRCLED[i], b.replace(drop_marker, ''))
                for i, b in enumerate(bodies))
            parts.append('### %s 标题\n- **以下不判X**（原例外内化）：%s\n' %
                         (sid, line))
        if drop_ordinal:  # 制造缺号：删掉 P019 的 ②
            parts[0] = parts[0].replace('②高密度信息章；', '')
        return '\n'.join(parts)

    run('基线同形桩 ⇒ 绿', stub(), 0)
    run('删「经多卷积累」⇒ 红（跨片依赖少 1）',
        stub(drop_marker='经多卷积累'), 1, '跨片依赖分布')
    run('删 P019 ② ⇒ 红（序号缺号 + 条款数）',
        stub(drop_ordinal=True), 1, '条款数')
    run('删整段 P037 ⇒ 红（底表 ID 缺失）',
        stub(drop_section=True), 1, '例外段缺失')
    run('空文件 ⇒ rc=2（空分母守卫）', '', 2)

    failed = [c for c in cases if not c[3]]
    for label, rc, expect, ok, violations in cases:
        print('%s %s: rc=%d(期望%d) %s' %
              ('PASS' if ok else 'FAIL', label, rc, expect,
               violations if not ok else ''))
    return 0 if not failed else 1


def main():
    ap = argparse.ArgumentParser(description='L0-b 分片外依赖静态审计')
    ap.add_argument('--root', default='.', help='项目根（默认当前目录）')
    ap.add_argument('--files', nargs='*', default=None,
                    help='手动指定手册文件（覆盖 --root 推导）')
    ap.add_argument('--out', default='outputs/gate/l0b_audit.json')
    ap.add_argument('--selftest', action='store_true',
                    help='跑负向变异自检，不写真报告')
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    paths = args.files or default_files(args.root)
    sections, errors = scan(paths)
    report, rc = audit(sections, errors)
    out = args.out if os.path.isabs(args.out) else os.path.join(args.root, args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    io.open(out, 'w', encoding='utf-8', newline='\n').write(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('L0-b 审计：段 %d / 条款 %d / 跨片命中 %d / 违规 %d ⇒ rc=%d' %
          (report['denominator']['sectionsFound'],
           report['denominator']['clausesFound'],
           len(report['crossShardHits']),
           len(report['violations']), rc))
    for v in report['violations']:
        print('  - ' + v)
    print('报告: %s' % out)
    return rc


if __name__ == '__main__':
    sys.exit(main())
