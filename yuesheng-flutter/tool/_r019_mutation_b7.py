# -*- coding: utf-8 -*-
"""R-019 批次七（buildSystemPromptV2 / shouldUnlockSyndrome / _collectOptionalFieldDrifts）判据级变异验证。"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

MUTATIONS = [
    ('lib/services/skill_dispatcher.dart',
     'test/services/skill_dispatcher_assembly_test.dart', [
        ('M1 L1 空 skill 误加',
         '  for (final skillId in l1SkillIds) {\n'
         '    final skill = getSkill(skillId);\n'
         '    if (skill != null) {\n'
         '      chunks.add(skill.content);\n'
         '      loadedIds.add(skillId);\n'
         '    }\n'
         '  }',
         '  for (final skillId in l1SkillIds) {\n'
         '    final skill = getSkill(skillId);\n'
         '    if (skill == null) {\n'
         '      chunks.add(skill.content);\n'
         '      loadedIds.add(skillId);\n'
         '    }\n'
         '  }'),
        ('M2 L2 阶段裁切失效',
         '      chunks.add(skill.contentForPhase?.call(ctx.phase) ?? skill.content);',
         '      chunks.add(skill.content);'),
        ('M3 attitude 档位不注入',
         '  if (attitudeSkill != null) {\n'
         '    chunks.add(attitudeSkill.content);\n'
         '    loadedIds.add(attitudeKey);\n'
         '  }',
         '  if (attitudeSkill != null) {\n'
         '    loadedIds.add(attitudeKey);\n'
         '  }'),
    ]),
    ('lib/services/diagnosis_service.dart',
     'test/services/diagnosis_service_test.dart', [
        ('M1 连续失败判定反转',
         "      if (trainingRecords[i]['result'] == 'failed') {",
         "      if (trainingRecords[i]['result'] != 'failed') {"),
        ('M2 连续失败阈值 >',
         '        consecutiveFailedTrainings >= DiagnosisLock.consecutiveFailThreshold ||\n'
         '        disputeCount >= DiagnosisLock.disputeThreshold;',
         '        consecutiveFailedTrainings > DiagnosisLock.consecutiveFailThreshold ||\n'
         '        disputeCount >= DiagnosisLock.disputeThreshold;'),
        ('M3 质疑筛选反转',
         "        .where((r) => r['action'] == 'disputed')",
         "        .where((r) => r['action'] != 'disputed')"),
        ('M4 症候匹配恒真',
         "        (id) => id is String && effectiveSyndromeId(id) == syndromeId,",
         "        (id) => id is String,"),
    ]),
    ('lib/services/diagnosis_validator.dart',
     'test/services/diagnosis_type_drift_test.dart', [
        ('M1 顶层字段任意值报漂移',
         '    final v = data[field];\n'
         '    if (v != null && v is! String) {',
         '    final v = data[field];\n'
         '    if (v != null) {'),
        ('M2 reader_impact 判定反转',
         '    final ri = syndrome[\'reader_impact\'];\n'
         '    if (ri != null && ri is! String) {',
         '    final ri = syndrome[\'reader_impact\'];\n'
         '    if (ri != null && ri is String) {'),
        ('M3 N3-a 越界判定反转',
         '  if (ctf is String && !syndromeIdSet.contains(ctf)) {',
         '  if (ctf is String && syndromeIdSet.contains(ctf)) {'),
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
