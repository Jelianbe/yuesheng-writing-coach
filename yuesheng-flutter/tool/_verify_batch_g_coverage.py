# -*- coding: utf-8 -*-
"""批次 G 复检：补测判据的分支级变异验证。

背景（2026-09-04 交接）：批次 G 给两个判据真空点补测试——
  G-1  _parseEvents 的 cause 双键兼容（3-D4 正路径此前无判据锚定）
  G-2  buildEvaluationSummary 此前 test/ 零直接引用（V4.20 真空函数）

本脚本对每个新判据打一个**判据级变异**，验证新用例真能拦（V4.21）：
拦住 = 判据锚定成立；漏网 = 用例是虚覆盖（或变异等价，须先分清，V4.16）。

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失/不唯一显式报错。
按 V4.14：锚点必须唯一（多行块或长表达式）。
按 V4.16：判据带 [E] 失败标记；变异须非等价（round→floor 在 0.8 处等价，
         故达标率文本变异采用删空格而非换舍入函数）。
按 V4.17：多行锚点按文件实际行尾自适应。
按 V4.18：跑 flutter test 清空会话代理 + 先做基线健康校验（不绿即 abort，
         防 [E] 假绿）。

用法：python tool/_verify_batch_g_coverage.py
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

F_SRC = 'lib/services/fact_validator.dart'
T_SRC = 'lib/services/training_evaluator.dart'

F_TESTS = ['test/services/fact_validator_test.dart']
T_TESTS = ['test/services/training_evaluator_test.dart']

# (ID, 源文件, 原文本, 变异文本, 判据说明, [测试文件])
MUTATIONS = [
    # ── G-1: _parseEvents cause 双键兼容（批次 3-D4）──
    ('G1-M1 驼峰采信', F_SRC,
     "(e['cause_event_name'] as String? ?? e['causeEventName'] as String?)",
     "(e['cause_event_name'] as String?)",
     'causeEventName 非空值必须被采信（拦 #F10）', F_TESTS),
    ('G1-M2 蛇形优先', F_SRC,
     "(e['cause_event_name'] as String? ?? e['causeEventName'] as String?)",
     "(e['causeEventName'] as String? ?? e['cause_event_name'] as String?)",
     '双键同给非空 → 蛇形优先（拦 #F11）', F_TESTS),
    ('G1-M3 空缺省', F_SRC,
     "final cause = (causeEventName?.isEmpty ?? true) ? null : causeEventName;",
     "final cause = (causeEventName?.isEmpty ?? true) ? '兜底' : causeEventName;",
     '无 cause 键 → null 而非塞值（拦 #F12）', F_TESTS),

    # ── G-2: buildEvaluationSummary 组装层 ──
    ('G2-D1 除零保护', T_SRC,
     "final passRate = inputs.passRateInput.totalCount > 0\n"
     "      ? inputs.passRateInput.passCount / inputs.passRateInput.totalCount\n"
     "      : 0.0;",
     "final passRate = inputs.passRateInput.passCount\n"
     "      / inputs.passRateInput.totalCount;",
     'totalCount=0 → 0% 而非 NaN 进 prompt（拦 #S2）', T_TESTS),
    ('G2-D2 干预建议行', T_SRC,
     "if (deterioration.signal != null) {\n"
     "    lines.add('干预建议: ${deterioration.intervention}');\n"
     "  }",
     "if (false) {\n"
     "    lines.add('干预建议: ${deterioration.intervention}');\n"
     "  }",
     '有恶化信号 → 干预建议行出现（拦 #S3）', T_TESTS),
    ('G2-D3 表述约束块', T_SRC,
     "if (minData.fallbackPhrases.isNotEmpty) {\n"
     "    lines.add('表述约束:')",
     "if (false) {\n"
     "    lines.add('表述约束:')",
     '数据不足 → 表述约束块注入（拦 #S4）', T_TESTS),
    ('G2-D4 达标率文本', T_SRC,
     "'达标率: ${inputs.passRateInput.passCount}"
     "/${inputs.passRateInput.totalCount}",
     "'达标率:${inputs.passRateInput.passCount}"
     "/${inputs.passRateInput.totalCount}",
     '达标率行文本格式契约（拦 #S1）', T_TESTS),
]


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
    r = subprocess.run([FLUTTER, 'test'] + test_files, env=env,
                       capture_output=True, text=True)
    return (r.stdout or '') + (r.stderr or '')


def main():
    cache = {}
    for _, src, _, _, _, _ in MUTATIONS:
        if src not in cache:
            with io.open(src, encoding='utf-8', newline='') as f:
                cache[src] = f.read()

    print('=' * 70)
    print('批次 G 补测判据变异验证（V4.21）')
    print('拦住 = 新用例判据锚定成立；漏网 = 虚覆盖或变异等价，须排查')
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
                base_cache[key] = 'All tests passed' in out
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
                caught = any('[E]' in line for line in out.splitlines())
                results.append((mid, why, '真覆盖' if caught else '虚覆盖'))
                print('  [%s] %s → %s' % (
                    mid, '变红（拦住）' if caught else '仍全绿（漏网）',
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
        print('  %-18s %-8s  %s' % (mid, v, why))
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
