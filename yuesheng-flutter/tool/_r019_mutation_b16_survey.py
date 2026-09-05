# -*- coding: utf-8 -*-
"""批次十六 5 目标变异摸底（V4.20 方法论）：editor/teacher validator + streamChat。"""
import io
import os
import subprocess

MUTATIONS = [
    (
        'lib/services/editor_validator.dart',
        'test/services/teacher_service_test.dart test/services/editor_service_test.dart',
        [
            ('E1 根对象类型反转', "  if (raw is! Map<String, dynamic>) {\n    return EditorValidationResult(", "  if (raw is Map<String, dynamic>) {\n    return EditorValidationResult("),
            ('E2 observations 下限放宽', "  if (obsList.length < 3) {", "  if (obsList.length < 1) {"),
            ('E3 dimension 白名单反转', "  if (d is String && _isValidDimension(d)) {", "  if (d is String && !_isValidDimension(d)) {"),
        ],
    ),
    (
        'lib/services/teacher_validator.dart',
        'test/services/teacher_service_test.dart test/services/teacher_consistency_test.dart test/services/teacher_validator_location_test.dart',
        [
            ('T1 根对象类型反转', "  if (raw is! Map<String, dynamic>) {\n    return TeacherValidationResult(", "  if (raw is Map<String, dynamic>) {\n    return TeacherValidationResult("),
            ('T2 task_type 白名单反转', "    if (_isValidTaskType(ttT)) {", "    if (!_isValidTaskType(ttT)) {"),
        ],
    ),
    (
        'lib/services/llm_client.dart',
        'test/services/llm_retry_test.dart',
        [
            ('L1 配置未设反转', "    if (cfg == null) throw Exception('API 配置未设置');", "    if (cfg != null) throw Exception('API 配置未设置');"),
            ('L2 语义重试判定反转', "      if (emitted) throw LlmNonRetryableException(e);", "      if (!emitted) throw LlmNonRetryableException(e);"),
            ('L3 取消判定反转', "    if (cancelToken?.isCancelled ?? false) {", "    if (!(cancelToken?.isCancelled ?? false)) {"),
            ('L4 DONE 分支反转', "          if (data == '[DONE]') {", "          if (data != '[DONE]') {"),
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
        capture_output=True, text=True, timeout=400, shell=True, env=env,
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
