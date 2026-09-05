# -*- coding: utf-8 -*-
"""R-019 批次十一变异验证：resolveTeachingFocus / applyPhaseMigration / buildReferencesContext。
范式同 b10：注入变异 -> 跑对应测试文件 -> 'All tests passed!' in out 判定漏网。"""
import io
import os
import subprocess

MUTATIONS = [
    (
        'lib/services/focus_resolver.dart',
        'test/services/focus_resolver_coverage_test.dart',
        [
            (
                'M1 不在池维持条件删 userOverride',
                '  // 训练中 + 用户切换 + 不在池中 → 拒绝，维持原 focus（5.7.2 第 2 行）\n  if (training && hasUserOverride) {',
                '  // 训练中 + 用户切换 + 不在池中 → 拒绝，维持原 focus（5.7.2 第 2 行）\n  if (training) {',
            ),
            (
                'M2 _findProblem 返回不匹配项',
                '  for (final p in problems) {\n    if (p.syndromeId == id) return p;',
                '  for (final p in problems) {\n    if (p.syndromeId != id) return p;',
            ),
            (
                'M3 fallback 空 id 也标 fallback',
                '    source: fb.id != null ? FocusSource.fallback : FocusSource.none,',
                '    source: FocusSource.fallback,',
            ),
        ],
    ),
    (
        'lib/services/diagnosis_committer.dart',
        'test/services/chat_service_phase_migration_test.dart',
        [
            (
                'M4 阶段不变也置迁移',
                '      if (prevPhaseValue != effectivePhase.value) {',
                '      if (prevPhaseValue == effectivePhase.value) {',
            ),
            (
                'M5 达标率 == 不迁移',
                '    if (passRate < EvaluationThresholds.phasePassRate) {',
                '    if (passRate > EvaluationThresholds.phasePassRate) {',
            ),
            (
                'M6 beginner 不落库反转',
                '    if (resolverResult.effectiveBeginnerLevel != null) {',
                '    if (resolverResult.effectiveBeginnerLevel == null) {',
            ),
        ],
    ),
    (
        'lib/services/chat_context_builder.dart',
        'test/services/chat_context_builder_excerpt_test.dart',
        [
            (
                'M7 预算主次反转',
                '  if (primaryRefs.isEmpty) {',
                '  if (primaryRefs.isNotEmpty) {',
            ),
            (
                'M8 章节锚点忽略 chapterId',
                '  if (ref.isPrimary == 1 && anchor != null && anchor.chapterId == ref.refId) {',
                '  if (ref.isPrimary == 1 && anchor != null) {',
            ),
            (
                'M9 空简介也输出',
                '  if (detail.description != null && detail.description!.isNotEmpty) {',
                '  if (detail.description != null) {',
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
        env={k: v for k, v in os.environ.items()},
    )
    return r.stdout + r.stderr


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
                print('\n'.join(out.splitlines()[-5:]))
            write(src, t)
    finally:
        write(src, orig)

print('变异验证完成')
