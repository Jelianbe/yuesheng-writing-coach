# -*- coding: utf-8 -*-
"""R-019 批次十二变异验证：buildTrainingInputForActiveSyndrome / buildStructuredSyndromeContext / applyFactExtractionFromContent。
范式：注入变异 -> 跑对应测试文件 -> 'All tests passed!' in out 判定漏网。try/finally 恢复 + INJECT-FAILED 锚点校验。"""
import io
import os
import subprocess

MUTATIONS = [
    (
        'lib/services/training_input_builder.dart',
        'test/services/training_input_builder_test.dart',
        [
            (
                'M1 数据不足阈值 < -> <=',
                '  if (diagnosisCount < _kMinDiagnosisCountForTrend) return null;',
                '  if (diagnosisCount <= _kMinDiagnosisCountForTrend) return null;',
            ),
            (
                'M2 连败/连赢计数 == result -> != result',
                "    if (trainingRecords[i]['result'] == result) {",
                "    if (trainingRecords[i]['result'] != result) {",
            ),
            (
                'M3 起始状态兜底 || -> &&',
                '  if (persisted == null || persisted.isEmpty) {',
                '  if (persisted == null && persisted.isEmpty) {',
            ),
            (
                'M4 passRate 除变乘',
                '    passRate: totalCount > 0 ? passCount / totalCount : 0.0,',
                '    passRate: totalCount > 0 ? passCount * totalCount : 0.0,',
            ),
        ],
    ),
    (
        'lib/services/chat_context_builder.dart',
        'test/syndrome_technique_knowledge_test.dart',
        [
            (
                'M5 非焦点预算池上界失效（clamp 上界归 0）',
                '    ContextBudget.nonFocusSummaryPoolBudget,',
                '    0,',
            ),
            (
                'M6 焦点分支 isFocus -> !isFocus',
                '    final isFocus = focusEnabled && p.syndromeId == focusId;',
                '    final isFocus = !(focusEnabled && p.syndromeId == focusId);',
            ),
        ],
    ),
    (
        'lib/services/diagnosis_committer.dart',
        'test/services/chat_service_fact_coverage_t2_4_test.dart',
        [
            (
                'M7 chapter 主引用判定 || -> &&',
                "    if (pRef == null || pRef.refType != 'chapter') return;",
                "    if (pRef == null && pRef.refType != 'chapter') return;",
            ),
            (
                'M8 事件事实 causeName 跳过 == null -> != null',
                '      if (causeName == null) continue;',
                '      if (causeName != null) continue;',
            ),
        ],
    ),
]


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


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


# 基线健康校验：无变异时三测试须 All tests passed
print('=== 基线健康校验 ===')
for _, test, _ in MUTATIONS:
    out = run_test(test)
    ok = 'All tests passed!' in out
    print(f'[{"OK" if ok else "FAIL"}] {test}')
    if not ok:
        print('\n'.join(out.splitlines()[-8:]))
        raise SystemExit('基线不健康，abort')

print('=== 变异验证 ===')
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

print('变异验证完成')
