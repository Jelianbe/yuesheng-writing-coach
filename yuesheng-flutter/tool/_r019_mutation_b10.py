# -*- coding: utf-8 -*-
"""R-019 批次十变异验证：resolvePhaseMapper / validateOutlineSchema / formatProfileText。
范式：注入变异 -> 跑对应测试文件 -> 'All tests passed!' in out 判定漏网。
try/finally 恢复 + INJECT-FAILED 锚点校验。"""
import io
import subprocess
import sys

MUTATIONS = [
    (
        'lib/services/phase_mapper_resolver.dart',
        'test/services/phase_mapper_resolver_test.dart',
        [
            (
                'M1 N3 降级阈值 <-> <=',
                '      consecutiveFailedTrainings < n3DowngradeThreshold ||',
                '      consecutiveFailedTrainings <= n3DowngradeThreshold ||',
            ),
            (
                'M2 无信号判定 || -> &&',
                '  if (suggestedPhase != null || suggestedBeginnerLevel != null) return null;',
                '  if (suggestedPhase != null && suggestedBeginnerLevel != null) return null;',
            ),
            (
                'M3 规则2 suggestedPhase != null -> == null',
                '  if (suggestedPhase != null) {',
                '  if (suggestedPhase == null) {',
            ),
        ],
    ),
    (
        'lib/services/outline_validator.dart',
        'test/services/outline_validator_test.dart',
        [
            (
                'M4 type 校验删 !',
                '  if (type is! String || !kValidEntityTypes.contains(type)) {',
                '  if (type is! String || kValidEntityTypes.contains(type)) {',
            ),
            (
                'M5 impression text 空串校验删',
                '    if (text is! String || text.trim().isEmpty) {',
                '    if (text is! String) {',
            ),
            (
                'M6 matched_entity_id 校验反转',
                '  if (matched != null && matched is! String) {',
                '  if (matched != null && matched is String) {',
            ),
        ],
    ),
    (
        'lib/services/student_profile_format.dart',
        'test/services/student_profile_c71_test.dart',
        [
            (
                'M7 认知风格段 onboarding 条件删',
                '  if (profile.cognitiveStyle == null || onboarding != null) return;',
                '  if (profile.cognitiveStyle == null) return;',
            ),
            (
                'M8 状态评估 totalDiagnoses >= -> >',
                '  if (totalDiagnoses >= 3) {',
                '  if (totalDiagnoses > 3) {',
            ),
            (
                'M9 症候分组 ??= -> =',
                '    byState[agg.teachingState] ??= <SyndromeAggregation>[];',
                '    byState[agg.teachingState] = <SyndromeAggregation>[];',
            ),
        ],
    ),
]


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def run_test(test_file):
    r = subprocess.run(
        f'flutter test {test_file} --no-pub',
        capture_output=True, text=True, timeout=300, shell=True,
        env={k: v for k, v in __import__('os').environ.items()},
    )
    return r.stdout + r.stderr


escaped = []
try:
    for src, test, cases in MUTATIONS:
        orig = read(src)
        try:
            for name, anchor, mutated in cases:
                t = read(src)
                if anchor not in t:
                    print(f'INJECT-FAILED {name}: 锚点缺失')
                    continue
                write(src, t.replace(anchor, mutated, 1))
                out = run_test(test)
                leaked = 'All tests passed!' in out
                print(f'[{"漏网" if leaked else "拦截"}] {name}')
                if leaked:
                    print('  --- 输出尾部 ---')
                    print('\n'.join(out.splitlines()[-6:]))
                write(src, t)
        finally:
            write(src, orig)
finally:
    pass

print('变异验证完成')
