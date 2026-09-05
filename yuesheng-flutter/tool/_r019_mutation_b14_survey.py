# -*- coding: utf-8 -*-
"""批次十四 _validateDiagnosis / validateDiagnosisSchema 变异摸底（V4.20 方法论）。"""
import io
import os
import subprocess

MUTATIONS = [
    (
        'lib/services/diagnosis_validator.dart',
        'test/services/diagnosis_validator_test.dart',
        [
            ('V1 根对象类型反转', '  if (raw is! Map<String, dynamic>) {', '  if (raw is Map<String, dynamic>) {'),
            ('V2 syndromes 空数组不拒', '  if (syndromes is! List || syndromes.isEmpty) {', '  if (syndromes is! List) {'),
            ('V3 syndrome 元素非对象不拒', "  if (s is! Map<String, dynamic>) {\n    errors.add(ValidationError(field: 'syndromes[$i]', message: '必须为对象'));", "  if (s is Map<String, dynamic>) {\n    errors.add(ValidationError(field: 'syndromes[$i]', message: '必须为对象'));"),
            ('V4 syndrome_id 空串不拒', "(s['syndrome_id'] as String).isEmpty) {", "(s['syndrome_id'] as String).isEmpty == false) {"),
            ('V5 severity 白名单放宽', "!['L1', 'L2', 'L3'].contains(sev)) {", "!['L1', 'L2', 'L3', 'L9'].contains(sev)) {"),
            ('V6 confidence 上界放宽', "conf is! num || conf < 0 || conf > 1) {", "conf is! num || conf < 0) {"),
        ],
    ),
    (
        'lib/services/diagnosis_parser.dart',
        'test/services/diagnosis_reject_reason_test.dart',
        [
            ('V7 _validateDiagnosis confidence 上界放宽', "confidence is! num || confidence < 0 || confidence > 1) {", "confidence is! num || confidence < 0) {"),
            ('V8 _validateDiagnosis suggested_actions 放宽', "suggestedActionsRaw is! List ||", "suggestedActionsRaw is! List && false ||"),
            ('V9 _validateDiagnosis 根对象类型反转', "  if (raw is! Map<String, dynamic>) {\n    return const _DiagnosisValidation.reject('root_not_object');", "  if (raw is Map<String, dynamic>) {\n    return const _DiagnosisValidation.reject('root_not_object');"),
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
