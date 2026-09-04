# -*- coding: utf-8 -*-
"""R-019 安全区「覆盖摸底」——判定剩余函数是真空还是虚覆盖（V4.20）。

不做重构，只做体检：对安全区剩余的服务层函数各注入一处判据级变异，
看现有测试能否拦住。拦住 = 真空（有断言锚定）；漏网 = 虚覆盖
（测试没走到，或走了没断言），重构前必须先补测试。

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失显式报错。
按 V4.16：判据必须带 flutter test 的失败标记 [E]。
按 V4.18：跑 flutter test 必须清空会话代理，且先做基线健康校验——
加载失败的行同样带 [E]，会让「拦截成功」假绿。

用法：python tool/_survey_r019_coverage.py
"""
import io
import os
import shutil
import subprocess
import sys

FLUTTER = (
    shutil.which('flutter.bat')
    or shutil.which('flutter')
    or r'D:\flutter\bin\flutter.bat'
)

# (标签, 源文件, 原文本, 变异文本, 判据说明, [测试文件])
MUTATIONS = [
    ('_updateDiagnosisSummary',
     'lib/data/repositories/diagnosis_repository.dart',
     'active.take(3)', 'active.take(2)', 'top_syndromes 取前 3',
     ['test/data/repositories/diagnosis_repository_test.dart']),
    ('interventionLevelForTrainingCount',
     'lib/services/syndrome_skill_levels.dart',
     'if (relapse ?? false) return InterventionLevel.iDo;',
     'if (relapse ?? true) return InterventionLevel.iDo;',
     'relapse 判据（未知 → iDo）',
     ['test/services/syndrome_skill_levels_test.dart']),
    ('validateGenuiComponent',
     'lib/services/genui_validator.dart',
     "(m['options'] as List).length < 2",
     "(m['options'] as List).length < 1",
     'quiz options 至少 2 项',
     ['test/services/genui_parser_test.dart',
      'test/contracts/genui_capability_test.dart']),
    ('detectDeterioration',
     'lib/services/training_evaluator.dart',
     'consecutiveFailures >= 2)', 'consecutiveFailures >= 1)',
     '连续失败门槛 2',
     ['test/services/training_evaluator_test.dart']),
    ('checkTeacherConsistency',
     'lib/services/teacher_validator.dart',
     "final hasError = violations.any((v) => v.severity == 'error');",
     "final hasError = violations.any((v) => v.severity == 'warn');",
     'error 级违规才算不通过',
     ['test/services/teacher_validator_location_test.dart',
      'test/corpus_teacher_acceptance_test.dart']),
    ('splitContent',
     'lib/services/progressive_diagnosis.dart',
     'if (content.length <= kDiagnosisChunkSize) {',
     'if (content.length < kDiagnosisChunkSize) {',
     '短文本直接返回（<= 边界）',
     ['test/services/progressive_diagnosis_test.dart',
      'test/services/progressive_chunk_syndrome_coverage_test.dart']),
    ('buildEvaluationSummary',
     'lib/services/training_evaluator.dart',
     'final passRate = inputs.passRateInput.totalCount > 0',
     'final passRate = inputs.passRateInput.totalCount >= 0',
     'totalCount=0 的除零保护',
     ['test/services/training_evaluator_test.dart']),
    ('_parseEvents',
     'lib/services/fact_validator.dart',
     "(e['cause_event_name'] as String? ?? e['causeEventName'] as String?)",
     "(e['cause_event_name'] as String?)",
     'cause_event_name / causeEventName 双键支持',
     ['test/services/fact_validator_test.dart']),
]


def run_tests(test_files):
    env = dict(os.environ)
    for k in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy'):
        env.pop(k, None)
    env['NO_PROXY'] = 'localhost,127.0.0.1'
    r = subprocess.run([FLUTTER, 'test'] + test_files, env=env,
                       capture_output=True, text=True)
    return (r.stdout or '') + (r.stderr or '')


def main():
    cache = {}
    for _, src, _, _, _, _ in MUTATIONS:
        if src not in cache:
            with io.open(src, encoding='utf-8', newline='') as f:
                cache[src] = f.read()

    print('=' * 66)
    print('R-019 安全区覆盖摸底（V4.20：虚覆盖体检）')
    print('=' * 66)

    results = []
    try:
        for label, src, old, new, why, tests in MUTATIONS:
            original = cache[src]
            # 基线：该组测试在原始源码下是否全绿
            base = run_tests(tests)
            base_clean = 'All tests passed' in base
            if not base_clean:
                print('\n[%s] ABORT：基线就不绿（环境问题），跳过' % label)
                print(base[-400:])
                results.append((label, why, '基线异常'))
                continue

            if old not in original:
                print('\n[%s] INJECT-FAILED：锚点未找到' % label)
                print('  锚点: %r' % old[:70])
                results.append((label, why, '锚点缺失'))
                continue

            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(original.replace(old, new, 1))
            try:
                out = run_tests(tests)
                caught = any('[E]' in line for line in out.splitlines())
                verdict = '真空' if caught else '虚覆盖'
                print('\n[%s]' % label)
                print('  判据：%s' % why)
                print('  变异后测试：%s → %s'
                      % ('变红' if caught else '仍全绿', verdict))
                results.append((label, why, verdict))
            finally:
                with io.open(src, 'w', encoding='utf-8', newline='') as f:
                    f.write(original)
    finally:
        for src, content in cache.items():
            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(content)

    same = all(io.open(s, encoding='utf-8', newline='').read() == c
               for s, c in cache.items())
    print('\n' + '=' * 66)
    print('源码恢复字节一致：%s' % same)
    print('=' * 66)
    print('%-40s %-10s' % ('函数', '判定'))
    print('-' * 66)
    for label, why, verdict in results:
        print('%-40s %-10s  (%s)' % (label, verdict, why))
    return 0 if same else 1


if __name__ == '__main__':
    sys.exit(main())
