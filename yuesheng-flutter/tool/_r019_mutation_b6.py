# -*- coding: utf-8 -*-
"""R-019 批次六（comprehensiveJudgment / getWritingCurve / _mapToParsedDiagnosis）判据级变异验证。"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

MUTATIONS = [
    ('lib/services/training_evaluator.dart',
     'test/services/training_evaluator_test.dart', [
        ('M1 明显改善达标率阈值 0.6→0.7',
         '  if (passRateVal >= 0.6 && stabilityTrend == TrendJudgment.improving) {',
         '  if (passRateVal >= 0.7 && stabilityTrend == TrendJudgment.improving) {'),
        ('M2 恶化趋势阈值 <0.2→<0.5',
         '  if (passRateVal < 0.2 && stabilityTrend == TrendJudgment.worsening) {',
         '  if (passRateVal < 0.5 && stabilityTrend == TrendJudgment.worsening) {'),
        ('M3 可能恶化边界 <=0.4→<=0.3',
         '  return passRateVal <= 0.4 && stabilityTrend == TrendJudgment.worsening\n'
         '      ? ComprehensiveJudgment.possibleWorsening\n'
         '      : ComprehensiveJudgment.stable;',
         '  return passRateVal <= 0.3 && stabilityTrend == TrendJudgment.worsening\n'
         '      ? ComprehensiveJudgment.possibleWorsening\n'
         '      : ComprehensiveJudgment.stable;'),
        ('M4 稳定达标率下界 <0.6→<=0.6',
         '  if (passRateVal >= 0.4 && passRateVal < 0.6) {',
         '  if (passRateVal >= 0.4 && passRateVal <= 0.6) {'),
    ]),
    ('lib/services/growth_service.dart',
     'test/services/growth_service_test.dart', [
        ('M1 空守卫 &&→||',
         "    if (rows.chapterRows.isEmpty && rows.diagnosisRows.isEmpty) return const [];",
         "    if (rows.chapterRows.isEmpty || rows.diagnosisRows.isEmpty) return const [];"),
        ('M2 日期序列少一天',
         '    for (var i = days - 1; i >= 0; i--) {',
         '    for (var i = days - 1; i > 0; i--) {'),
        ('M3 章节省字数忽略',
         '          wordCount: point.wordCount + row.read<int>(\'words\'),',
         '          wordCount: point.wordCount + 0,'),
    ]),
    ('lib/services/diagnosis_validator.dart',
     'test/services/diagnosis_type_drift_test.dart', [
        ('M1 next_step 类型检查移除',
         "  if (teachingPlan == null || teachingPlan['next_step'] is! String) return null;",
         "  if (teachingPlan == null) return null;"),
        ('M2 teaching_plan is Map 放宽',
         "  final plan = data['teaching_plan'] is Map<String, dynamic>\n"
         '      ? data[\'teaching_plan\'] as Map<String, dynamic>\n'
         '      : null;',
         "  final plan = data['teaching_plan'] is Map\n"
         '      ? data[\'teaching_plan\'] as Map<String, dynamic>\n'
         '      : null;'),
        ('M3 syndromes 映射跳过 fromJson',
         "    return Syndrome.fromJson(m);",
         "    return Syndrome(syndromeId: 'X', severity: SeverityLevel.l2);"),
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
