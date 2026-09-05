# -*- coding: utf-8 -*-
"""批次十五 buildStudentContext / _buildSyndromeDetail 变异摸底（V4.20 方法论，拆分后锚点更新）。"""
import io
import os
import subprocess

MUTATIONS = [
    (
        'lib/services/student_profile.dart',
        'test/services/student_profile_c71_test.dart test/services/student_profile_infer_test.dart',
        [
            ('M1 onboarding 加载反转', "  if (sessionId != null) {\n    final raw = await studentModelRepo.getOnboardingData(sessionId);", "  if (sessionId != null && false) {\n    final raw = await studentModelRepo.getOnboardingData(sessionId);"),
            ('M2 空返回判据反转', "  if (entries.isEmpty && effectiveOnboarding == null) {", "  if (entries.isEmpty) {"),
            ('M3 styleProfile 拼接恒等', "  return styleProfileText != null ? '$text\\n\\n$styleProfileText' : text;", "  return text;"),
            ('M4 totalSessions 清零', "    totalSessions: allSessionIds.length,", "    totalSessions: 0,"),
            ('M5 skipped 过滤反转', "  return (onboarding != null && !onboarding.skipped) ? onboarding : null;", "  return (onboarding != null && onboarding.skipped) ? onboarding : null;"),
        ],
    ),
    (
        'lib/services/evaluation_service.dart',
        'test/services/evaluation_service_test.dart',
        [
            ('M6 状态迁移不持久化', "        if (summary.teachingState != startingTeachingState) {", "        if (summary.teachingState == startingTeachingState) {"),
            ('M7 mastered 不解锁', "      if (state == TeachingState.mastered) {", "      if (state != TeachingState.mastered) {"),
            ('M8 totalCount 下限恒等', "    final totalCount = trainingInput.passRateInput.totalCount < 1\n        ? 1\n        : trainingInput.passRateInput.totalCount;", "    final totalCount = trainingInput.passRateInput.totalCount;"),
            ('M9 fallback trend 边界', "      trend: passRate >= EvaluationThresholds.passRateImproving", "      trend: passRate > EvaluationThresholds.passRateImproving"),
        ],
    ),
]


def read(p):
    return io.open(p, encoding='utf-8', newline='').read().replace('\r\n', '\n')


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def run_test(test_file):
    env = dict(os.environ)
    env.pop('HTTP_PROXY', None)
    env.pop('HTTPS_PROXY', None)
    r = subprocess.run(
        f'flutter test {test_file} --no-pub',
        capture_output=True, text=True, timeout=300, shell=True, env=env,
    )
    return r.stdout + r.stderr


def healthy(test_file):
    out = run_test(test_file)
    return 'All tests passed!' in out


for src, test, cases in MUTATIONS:
    if not healthy(test):
        print(f'基线健康校验失败（未变异即不通过）: {test}')
        continue
    orig = read(src)
    try:
        for name, anchor, mutated in cases:
            t = read(src)
            if anchor not in t:
                print(f'INJECT-FAILED {name}: 锚点缺失')
                continue
            write(src, t.replace(anchor, mutated, 1))
            out = run_test(test)
            ok = 'All tests passed!' in out
            print(f'[{"拦截" if not ok else "漏网"}] {name}')
    finally:
        write(src, orig)
print('摸底完成')
