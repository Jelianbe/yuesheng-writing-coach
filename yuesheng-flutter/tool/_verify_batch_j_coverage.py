# -*- coding: utf-8 -*-
"""批次 J 复检：服务层安全区清偿后的判据级变异验证（V4.21）。

覆盖范围（2026-09-04 批次 J-A）：
  J-1  _parseEvents 拆 3（_parseEvents / _extractEventFields / _extractEventMetadata）
  J-2  buildEvaluationSummary 拆 2（_computePassRate / _buildContextInjection）
  J-3  guardStream 补 2 例（onError 透传 / cancelOnError: false 契约）

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失/不唯一显式报错。
按 V4.14：锚点必须唯一（多行块）。
按 V4.18：跑 flutter test 清空会话代理 + 先做基线健康校验（不绿即 abort）。
按 V4.17：多行锚点按文件实际行尾自适应。
按 V4.21：每个补测判据都要打分支级变异（全拦才叫真覆盖）。

用法：python tool/_verify_batch_j_coverage.py
"""
import io
import os
import shutil
import subprocess
import sys

FLUTTER = (
    shutil.which('flutter_env.bat')
    or r'C:\Users\NewName\flutter_env.bat'
    or shutil.which('flutter.bat')
    or shutil.which('flutter')
    or r'D:\flutter\bin\flutter.bat'
)

FACT_SRC = 'lib/services/fact_validator.dart'
TRAIN_SRC = 'lib/services/training_evaluator.dart'
SVC_SRC = 'lib/services/stream_guard.dart'

FACT_TESTS = ['test/services/fact_validator_test.dart']
TRAIN_TESTS = ['test/services/training_evaluator_test.dart']
SVC_TESTS = ['test/stream_guard_test.dart']

# (ID, 源文件, 原文本, 变异文本, 判据说明, [测试文件])
MUTATIONS = [
    # ── J-1: _parseEvents 拆 3 ──
    # 锚点用「上下文缩进 + 后续一行」保证唯一（_parseSubplots / _parseCharacters 同款）
    ('J1-V1 列表校验', FACT_SRC,
     "List<EventFactUpdate> _parseEvents(\n"
     "  dynamic raw,\n"
     "  List<FactValidationError> errors,\n"
     ") {\n"
     "  if (raw is! List) return const [];",
     "List<EventFactUpdate> _parseEvents(\n"
     "  dynamic raw,\n"
     "  List<FactValidationError> errors,\n"
     ") {\n"
     "  if (raw is List) return const [];",
     '非 List 输入 → []（拦非法顶层，防全表通过）', FACT_TESTS),
    ('J1-V2 Map 校验', FACT_SRC,
     "    if (e is! Map<String, dynamic>) {\n"
     "      errors.add(FactValidationError(field: 'events[$i]', message: '必须是对象'));\n"
     "      continue;\n"
     "    }",
     "    if (false) {\n"
     "      errors.add(FactValidationError(field: 'events[$i]', message: '必须是对象'));\n"
     "      continue;\n"
     "    }",
     '非 Map 元素 → errors（拦 #F8 全非法丢弃）', FACT_TESTS),
    ('J1-V3 name 校验', FACT_SRC,
     "  if (name is! String || name.trim().isEmpty) {\n"
     "    errors.add(\n"
     "      FactValidationError(field: 'events[$i].name', message: '必须为非空字符串'),\n"
     "    );\n"
     "    return null;\n"
     "  }",
     "  if (false) {\n"
     "    errors.add(\n"
     "      FactValidationError(field: 'events[$i].name', message: '必须为非空字符串'),\n"
     "    );\n"
     "    return null;\n"
     "  }",
     'name 空 → errors + 跳过（拦 name 必填）', FACT_TESTS),
    ('J1-V4 eventType 双键', FACT_SRC,
     "  final eventType = e['event_type'] ?? e['eventType'];",
     "  final eventType = e['event_type'] ?? '';",
     'eventType 驼峰键丢失 → 必拒（拦 #F6 双键兼容）', FACT_TESTS),
    ('J1-V5 cause 双键', FACT_SRC,
     "  final causeEventName =\n"
     "      (e['cause_event_name'] as String? ?? e['causeEventName'] as String?)\n"
     "          ?.trim();",
     "  final causeEventName = e['cause_event_name'] as String?;",
     'cause 驼峰键丢失 → null（拦 #F10/F11 双键兼容）', FACT_TESTS),
    ('J1-V6 participants 过滤', FACT_SRC,
     "  final participants = participantsRaw is List\n"
     "      ? participantsRaw.whereType<String>().where((p) => p.isNotEmpty).toList()\n"
     "      : const <String>[];",
     "  final participants = participantsRaw is List\n"
     "      ? (participantsRaw as List).cast<String>()\n"
     "      : const <String>[];",
     'participants 非字符串/空串过滤丢（拦 #F9）', FACT_TESTS),

    # ── J-2: buildEvaluationSummary 拆 2 ──
    ('J2-V1 除零保护', TRAIN_SRC,
     "double _computePassRate(PassRateInput input) {\n"
     "  return input.totalCount > 0 ? input.passCount / input.totalCount : 0.0;\n"
     "}",
     "double _computePassRate(PassRateInput input) {\n"
     "  return input.passCount / input.totalCount;\n"
     "}",
     'totalCount=0 → 0 不 NaN（拦 #S2）', TRAIN_TESTS),
    ('J2-V2 头尾标记', TRAIN_SRC,
     "    '[训练评估（代码计算）]',",
     "    '',",
     'contextInjection 头标记（拦 #S1 startsWith）', TRAIN_TESTS),
    ('J2-V3 干预建议', TRAIN_SRC,
     "  if (deterioration.signal != null) {\n"
     "    lines.add('干预建议: ${deterioration.intervention}');\n"
     "  }",
     "  if (false) {\n"
     "    lines.add('干预建议: ${deterioration.intervention}');\n"
     "  }",
     '恶化信号 → 干预建议行（拦 #S3）', TRAIN_TESTS),
    ('J2-V4 表述约束', TRAIN_SRC,
     "  if (minData.fallbackPhrases.isNotEmpty) {\n"
     "    lines.add('表述约束:');\n"
     "    for (final p in minData.fallbackPhrases) {\n"
     "      lines.add('  - $p');\n"
     "    }\n"
     "  }",
     "  if (false) {\n"
     "    lines.add('表述约束:');\n"
     "    for (final p in minData.fallbackPhrases) {\n"
     "      lines.add('  - $p');\n"
     "    }\n"
     "  }",
     '数据不足 → 表述约束块（拦 #S4）', TRAIN_TESTS),

    # ── J-3: guardStream 补 2 例（拆不动，补强覆盖）──
    ('J3-V1 onError 透传', SVC_SRC,
     "    onError: (e, st) {\n"
     "      timer?.cancel();\n"
     "      controller.addError(e, st);\n"
     "    },",
     "    onError: (e, st) {\n"
     "      timer?.cancel();\n"
     "      // controller.addError(e, st);  // 变异：吞掉错误\n"
     "    },",
     'source 错误 → guarded 透传（拦 #G5）', SVC_TESTS),
    ('J3-V2 cancelOnError 契约', SVC_SRC,
     "    cancelOnError: false,",
     "    cancelOnError: true,",
     'cancelOnError: false 契约 → 错误后不自动断开（拦 #G6）', SVC_TESTS),
]

PROCESS_TIMEOUT_MARK = '__PROCESS_TIMEOUT__'
TEST_TIMEOUT_SEC = 240


def adapt_eol(text, eol):
    """把锚点里的 \\n 换成文件实际行尾（V4.17）。"""
    return text.replace('\n', eol) if eol != '\n' else text


def detect_eol(content):
    return '\r\n' if content.count('\r\n') >= content.count('\n') / 2 else '\n'


def run_tests(test_files):
    env = dict(os.environ)
    for k in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy'):
        env.pop(k, None)
    env['NO_PROXY'] = 'localhost,127.0.0.1'
    proc = subprocess.Popen(
        [FLUTTER, 'test'] + test_files, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        out, err = proc.communicate(timeout=TEST_TIMEOUT_SEC)
        return (out or '') + (err or '')
    except subprocess.TimeoutExpired:
        if os.name == 'nt':
            subprocess.run(
                ['taskkill', '/F', '/T', '/PID', str(proc.pid)],
                capture_output=True,
            )
        else:
            proc.kill()
        out, err = proc.communicate()
        return ((out or '') + (err or '') + PROCESS_TIMEOUT_MARK)


def main():
    cache = {}
    for _, src, _, _, _, _ in MUTATIONS:
        if src not in cache:
            with io.open(src, encoding='utf-8', newline='') as f:
                cache[src] = f.read()

    print('=' * 70)
    print('批次 J 服务层安全区变异验证（V4.21）')
    print('拦住 = 补测判据真覆盖；漏网 = 虚覆盖或变异等价')
    print('=' * 70)

    base_cache = {}
    results = []
    try:
        for mid, src, old, new, why, tests in MUTATIONS:
            original = cache[src]
            eol = detect_eol(original)
            o_a, n_a = adapt_eol(old, eol), adapt_eol(new, eol)

            key = (src, tuple(tests))
            if key not in base_cache:
                out = run_tests(list(tests))
                base_cache[key] = (
                    'All tests passed' in out
                    and PROCESS_TIMEOUT_MARK not in out
                )
                if not base_cache[key]:
                    print('\n[基线异常] %s — ABORT' % src)
                    print(out[-500:])
            if not base_cache[key]:
                results.append((mid, why, '基线异常'))
                continue

            if o_a not in original:
                print('\n[%s] INJECT-FAILED：锚点缺失（%r）' % (mid, o_a[:70]))
                results.append((mid, why, '锚点异常'))
                continue
            if original.count(o_a) != 1:
                print('\n[%s] INJECT-FAILED：锚点不唯一（%d 次）'
                      % (mid, original.count(o_a)))
                results.append((mid, why, '锚点异常'))
                continue

            mutated = original.replace(o_a, n_a, 1)
            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(mutated)
            try:
                out = run_tests(list(tests))
                caught = (
                    PROCESS_TIMEOUT_MARK in out
                    or any('[E]' in line for line in out.splitlines())
                )
                results.append((mid, why, '真覆盖' if caught else '虚覆盖'))
                print('  [%s] %s → %s' % (
                    mid, '变红/挂死（拦住）' if caught else '仍全绿（漏网）',
                    why))
            finally:
                with io.open(src, 'w', encoding='utf-8', newline='') as f:
                    f.write(original)
    finally:
        for src, content in cache.items():
            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(content)

    same = all(io.open(s, encoding='utf-8', newline='').read() == c
               for s, c in cache.items())

    print('\n' + '=' * 70)
    print('源码恢复字节一致：%s' % same)
    print('-' * 70)
    n_real = sum(1 for _, _, v in results if v == '真覆盖')
    n_virt = sum(1 for _, _, v in results if v == '虚覆盖')
    n_bad = len(results) - n_real - n_virt
    for mid, why, v in results:
        print('  %-22s %-8s  %s' % (mid, v, why))
    print('-' * 70)
    print('合计 %d：拦住 %d / 漏网 %d / 异常 %d'
          % (len(results), n_real, n_virt, n_bad))
    if n_virt:
        print('\n漏网判据（新用例未锚定，先排查是否变异等价）：')
        for mid, why, v in results:
            if v == '虚覆盖':
                print('  - [%s] %s' % (mid, why))
    return 0 if (same and n_virt == 0 and n_bad == 0) else 1


if __name__ == '__main__':
    sys.exit(main())