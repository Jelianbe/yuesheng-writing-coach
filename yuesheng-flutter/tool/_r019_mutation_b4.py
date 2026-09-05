# -*- coding: utf-8 -*-
"""R-019 批次四（generateReport / routeStyleTechniques / getGrowthOverview）判据级变异验证。"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

MUTATIONS = [
    ('lib/services/progress_service.dart',
     'test/services/progress_service_test.dart', [
        ('M1 解决率分母反转',
         '        ? (summary.resolvedProblems * 100 / summary.totalProblems).round()',
         '        ? (summary.resolvedProblems * 100 / (summary.totalProblems + 1)).round()'),
        ('M2 active 过滤反转',
         "        .where((p) => p.status == 'active')",
         "        .where((p) => p.status != 'active')"),
        ('M3 已解决段反转',
         '    if (resolved.isEmpty) return;',
         '    if (resolved.isNotEmpty) return;'),
    ]),
    ('lib/services/style_technique_router.dart',
     'test/style_technique_router_test.dart', [
        ('M1 内容优先级阈值',
         '        (severityRank[p.severity] ?? 0) >= 2 &&',
         '        (severityRank[p.severity] ?? 0) >= 3 &&'),
        ('M2 门控3 反转',
         '  if (focusSyndromeId == null) return false;',
         '  if (focusSyndromeId != null) return false;'),
        ('M3 满2即停阈值',
         '      if (candidates.length >= 2) return candidates;',
         '      if (candidates.length >= 3) return candidates;'),
    ]),
    ('lib/services/growth_service.dart',
     'test/services/growth_service_test.dart', [
        ('M1 训练计数反转',
         "              .where((r) => r['type'] == 'training')",
         "              .where((r) => r['type'] != 'training')"),
        ('M2 总字数默认值',
         "      totalWords: wordRow?.read<int>('total') ?? 0,",
         "      totalWords: wordRow?.read<int>('total') ?? 1,"),
        ('M3 阶段默认值反转',
         '          TeachingPhase.fromString(phaseRow?.read<String?>(\'phase\')) ??\n'
         '          TeachingPhase.p0Engage,',
         '          TeachingPhase.fromString(phaseRow?.read<String?>(\'phase\')) ??\n'
         '          TeachingPhase.p1Develop,'),
    ]),
]


def _flutter():
    for c in ['flutter', 'flutter.bat']:
        p = shutil.which(c)
        if p:
            return p
    raise RuntimeError('no flutter')


FLUTTER = _flutter()
total = 0
failed = []
for src_rel, test_rel, cases in MUTATIONS:
    src = ROOT / src_rel
    test = ROOT / test_rel
    orig = io.open(src, encoding='utf-8', newline='').read()
    eol = '\r\n' if orig.count('\r\n') >= orig.count('\n') / 2 else '\n'
    for name, anchor, mutated in cases:
        a, m = anchor.replace('\n', eol), mutated.replace('\n', eol)
        if a not in orig:
            print('INJECT-FAILED: [{}] 锚点未找到'.format(name))
            failed.append((name, '锚点缺失'))
            continue
        total += 1
        try:
            io.open(src, 'w', encoding='utf-8', newline='').write(orig.replace(a, m, 1))
            r = subprocess.run([FLUTTER, 'test', str(test), '--no-pub'],
                               cwd=str(ROOT), capture_output=True, text=True,
                               timeout=300, encoding='utf-8', errors='replace', shell=False)
            out = r.stdout + r.stderr
            if 'All tests passed!' in out:
                print('MUTATION-LOOSE: [{}] 漏网'.format(name))
                failed.append((name, '漏网'))
            else:
                print('MUTATION-KILL: [{}] 拦截 ✓'.format(name))
        finally:
            io.open(src, 'w', encoding='utf-8', newline='').write(orig)

print()
print('变异总数: {}, 未拦截: {}'.format(total, len(failed)))
for n, why in failed:
    print('  FAIL: {} — {}'.format(n, why))
sys.exit(1 if failed else 0)
