# -*- coding: utf-8 -*-
"""R-019 批次九（extractStyleFingerprint / applyOutlineExtraction / computeRoundEvaluation）判据级变异验证。"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

MUTATIONS = [
    ('lib/services/style_fingerprint.dart',
     'test/services/style_fingerprint_test.dart', [
        ('M1 样本不足守卫反转',
         '  if (t.length < kFingerprintMinChars) return null;',
         '  if (t.length >= kFingerprintMinChars) return null;'),
        ('M2 对话占比反转',
         '    if (_dialogueQuote.hasMatch(l)) dialogueLines++;',
         '    if (!_dialogueQuote.hasMatch(l)) dialogueLines++;'),
        ('M3 短句不建 bigram',
         '    if (cleaned.length < 2) continue;',
         ''),
    ]),
    ('lib/services/outline_service.dart',
     'test/services/outline_service_test.dart', [
        ('M1 别名匹配失效',
         '    // 2. 别名交集匹配\n'
         '    if (target == null) {\n'
         '      final probeKeys = {update.key, ...update.aliases};',
         '      // 2. 别名交集匹配\n'
         '      if (target == null && false) {\n'
         '        final probeKeys = {update.key, ...update.aliases};'),
        ('M2 重复印象去重失效',
         '      if (await _repo.hasImpression(target.id, im.text)) continue;',
         '      if (await _repo.hasImpression(target.id, im.text)) { }'),
        ('M3 幻觉 id 也接受',
         '    if (update.matchedEntityId != null &&\n'
         '        knownIds.contains(update.matchedEntityId)) {',
         '      if (update.matchedEntityId != null &&\n'
         '          !knownIds.contains(update.matchedEntityId)) {'),
    ]),
    ('lib/services/evaluation_service.dart',
     'test/services/evaluation_service_test.dart', [
        ('M1 空诊断不返回 null',
         '      final diagnoses = await _diagnosisRepo.listDiagnosisHistory(sessionId);\n'
         '      if (diagnoses.isEmpty) return null;',
         '      final diagnoses = await _diagnosisRepo.listDiagnosisHistory(sessionId);'),
        ('M2 round=0 也算严重度变化',
         '    if (round <= 0 || diagnoses.length < 2) return null;',
         '    if (round < 0 || diagnoses.length < 2) return null;'),
        ('M3 达标率除零路径',
         '  if (totalAttempt > 0) return totalPass / totalAttempt;',
         '  if (totalAttempt >= 0) return totalPass / totalAttempt;'),
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
    for name, anchor, mutated in cases:
        if anchor not in orig:
            print('INJECT-FAILED: [{}] 锚点未找到'.format(name))
            failed.append((name, '锚点缺失'))
            continue
        total += 1
        try:
            io.open(src, 'w', encoding='utf-8', newline='').write(orig.replace(anchor, mutated, 1))
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
