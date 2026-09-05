# -*- coding: utf-8 -*-
"""R-019 批次五（parseDiagnosis / commitDiagnosisWithHistory / detectVoiceDrift）判据级变异验证。"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

MUTATIONS = [
    ('lib/services/diagnosis_parser.dart',
     'test/services/diagnosis_parser_test.dart', [
        ('M1 无诊断块 FACT 剥离失效',
         "    displayContent: stripFactBlock(stripOutlineBlock(rawText)),",
         "    displayContent: stripOutlineBlock(rawText),"),
        ('M2 诊断块判定反转',
         '  if (startIndex == -1) return _parseNoMarker(rawText);',
         '  if (startIndex != -1) return _parseNoMarker(rawText);'),
        ('M3 json_decode 失败反转',
         '  if (!decoded.ok) {',
         '  if (decoded.ok) {'),
    ]),
    ('lib/services/diagnosis_service.dart',
     'test/services/diagnosis_service_test.dart', [
        ('M1 最高严重度边界 >=',
         '      if ((severityOrder[sev] ?? 0) > (severityOrder[maxSeverity] ?? 0)) {',
         '      if ((severityOrder[sev] ?? 0) >= (severityOrder[maxSeverity] ?? 0)) {'),
        ('M2 teaching_mode 默认值',
         "      'teaching_mode': input.teachingMode ?? 'socratic',",
         "      'teaching_mode': input.teachingMode ?? 'direct',"),
        ('M3 commit 失败不 return',
         '      return;\n'
         '    }\n'
         '\n'
         '    // 2. 追加 teaching_history',
         '    }\n'
         '\n'
         '    // 2. 追加 teaching_history'),
    ]),
    ('lib/services/style_fingerprint.dart',
     'test/services/style_fingerprint_test.dart', [
        ('M1 句长基线 0 边界',
         '  if (baseline.avgSentenceLength <= 0) return null;',
         '  if (baseline.avgSentenceLength < 0) return null;'),
        ('M2 对话配比阈值 <=',
         '  if ((current.dialogueRatio - baseline.dialogueRatio).abs() <\n'
         '      kDriftDialogueRatioAbs) {',
         '  if ((current.dialogueRatio - baseline.dialogueRatio).abs() <=\n'
         '      kDriftDialogueRatioAbs) {'),
        ('M3 简短/绵长判定 >',
         "  return '你惯用的句式偏${baseline.simpleSentenceRatio >= 0.5 ? '简短' : '绵长'}'\n",
         "  return '你惯用的句式偏${baseline.simpleSentenceRatio > 0.5 ? '简短' : '绵长'}'\n"),
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
