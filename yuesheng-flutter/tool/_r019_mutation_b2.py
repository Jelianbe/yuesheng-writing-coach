# -*- coding: utf-8 -*-
"""R-019 批次二（validateNaturalLanguage / callEditorStream / transitionTeachingState）拆分的判据级变异验证。"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

MUTATIONS = [
    ('lib/services/diagnosis_validator.dart', 'test/services/diagnosis_validator_test.dart', [
        ('M1 糖水词拦截反转',
         '  if (attitude != AttitudeLevel.sensei) return fixes;',
         '  if (attitude == AttitudeLevel.sensei) return fixes;'),
        ('M2 改写阈值边界失效',
         '    if (para.length > _kRewriteThreshold &&',
         '    if (para.length >= _kRewriteThreshold &&'),
        ('M3 动作码替换失效',
         '  out = out.replaceAllMapped(kActionCodeRe, (match) {',
         '  out = out.replaceAllMapped(kSyndromeCodeRe, (match) {'),
    ]),
    ('lib/services/editor_service.dart', 'test/services/editor_service_test.dart', [
        ('M1 observation 判定反转',
         "  if (parsed.observation == null) {",
         "  if (parsed.observation != null) {"),
        ('M2 硬限制校验反转',
         '  if (!hardLimit.passed) {',
         '  if (hardLimit.passed) {'),
        ('M3 拦截状态失效',
         '    if (inEditorBlock) return;',
         '    inEditorBlock = true;'),
    ]),
    ('lib/services/training_evaluator.dart', 'test/services/training_evaluator_test.dart', [
        ('M1 identified 前进反转',
         '  if (!input.trainingStarted) return null;',
         '  if (input.trainingStarted) return null;'),
        ('M2 低严重度边界失效',
         '        input.consecutiveLowSeverity >= 3 &&',
         '        input.consecutiveLowSeverity > 3 &&'),
        ('M3 通过次数边界失效',
         '  if (input.consecutiveLowSeverity >= 3 || input.consecutivePasses >= 5) {',
         '  if (input.consecutiveLowSeverity >= 3 || input.consecutivePasses > 5) {'),
    ]),
]


def _flutter_cmd():
    for cand in ['flutter', 'flutter.bat']:
        p = shutil.which(cand)
        if p:
            return p
    raise RuntimeError('找不到 flutter')


FLUTTER = _flutter_cmd()

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
            print('INJECT-FAILED: [{}] 锚点未找到: {}'.format(name, src_rel))
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
