# -*- coding: utf-8 -*-
"""批次 F 复检：分支级判据覆盖体检（V4.21 落地）。

与 _survey_r019_coverage.py 的区别：摸底脚本每个函数只打 **1 个** 判据，
只能证明「这一条判据被锚定」，不能证明整个函数是真覆盖。
本脚本对目标函数的 **每个分支** 各打一个判据级变异，
逐分支判定真/虚覆盖，作为重构前的准入依据。

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失显式报错。
按 V4.14：锚点必须唯一（stat/progress 的 label 行文本重复 → 用多行块）。
按 V4.16：判据必须带 flutter test 的失败标记 [E]；变异「漏网」先分清测试失灵
         还是变异等价——B11 因重构引入 switch 兜底而与白名单检查互为纵深防御，
         单点变异等价，故改按契约做双点变异（old 支持 [(o, n), ...] 列表）。
按 V4.17：工作区行尾不统一，多行锚点须按文件实际行尾自适应。
按 V4.18：跑 flutter test 必须清空会话代理，且先做基线健康校验。
按 V4.21：判据按**分支**给，每个分支至少一个——单点评据只证明那一条被锚定。

用法：python tool/_verify_batch_f_coverage.py
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

A_TESTS = ['test/services/syndrome_skill_levels_test.dart']
B_TESTS = ['test/services/genui_parser_test.dart',
           'test/contracts/genui_capability_test.dart']

A_SRC = 'lib/services/syndrome_skill_levels.dart'
B_SRC = 'lib/services/genui_validator.dart'

# 多行锚点：stat/progress/timeline 的字段校验块（含缩进与换行）
# 注意：缩进随重构后的方法体层级（4 空格），return 值已从 null 改 false。
# 整块匹配以保证唯一——单看 `if (m['label'] ...)` 在 stat/progress 里都出现。
STAT_BLOCK = (
    "if (m['label'] is! String) return false;\n"
    "    if (m['value'] is! num) return false;\n"
    "    if (m['max'] is! num) return false;"
)
PROGRESS_BLOCK = (
    "if (m['label'] is! String) return false;\n"
    "    if (m['status'] is! String) return false;"
)
TIMELINE_BLOCK = (
    "if (m['date'] is! String) return false;\n"
    "    if (m['title'] is! String) return false;"
)

# (ID, 源文件, 原文本, 变异文本, 判据说明, [测试文件])
MUTATIONS = [
    # ── A: interventionLevelForTrainingCount（9 个分支判据）──
    ('A1 D3-relapse', A_SRC,
     'if (relapse ?? false) return InterventionLevel.iDo;',
     'if (relapse ?? true) return InterventionLevel.iDo;',
     'relapse=true 才回退 I do', A_TESTS),
    ('A2 D3-L3', A_SRC,
     'if (currentSeverity == Severity.l3) return InterventionLevel.iDo;',
     'if (currentSeverity == Severity.l2) return InterventionLevel.iDo;',
     '仅 L3 回退（L2 不回退）', A_TESTS),
    ('A3 base-上界', A_SRC,
     'if (trainingCount >= 4) return InterventionLevel.youDo;',
     'if (trainingCount >= 5) return InterventionLevel.youDo;',
     '次数 ≥4 升 You do', A_TESTS),
    ('A4 base-下界', A_SRC,
     'if (trainingCount >= 2) return InterventionLevel.weDo;',
     'if (trainingCount >= 3) return InterventionLevel.weDo;',
     '次数 ≥2 升 We do', A_TESTS),
    ('A5 G1-门槛', A_SRC,
     'if (performance.consecutiveFails >= 3) return InterventionLevel.iDo;',
     'if (performance.consecutiveFails >= 4) return InterventionLevel.iDo;',
     'G1 连续 3 次未达标门槛', A_TESTS),
    ('A6 G2-上界', A_SRC,
     'if (performance.passRate < 0.5 && base != InterventionLevel.iDo) {',
     'if (performance.passRate < 0.9 && base != InterventionLevel.iDo) {',
     'G2 passRate ≥0.5 不降档', A_TESTS),
    ('A7 G3-下界', A_SRC,
     'if (performance.consecutiveFails >= 2 && base == InterventionLevel.youDo) {',
     'if (performance.consecutiveFails >= 1 && base == InterventionLevel.youDo) {',
     'G3 仅连续 1 次未达标时不触发', A_TESTS),
    ('A8 G4-下界', A_SRC,
     'performance.totalCount >= 1 &&',
     'performance.totalCount >= 2 &&',
     'G4 totalCount≥1 即可触发', A_TESTS),
    ('A9 G5-下界', A_SRC,
     'performance.totalCount >= 2 &&',
     'performance.totalCount >= 1 &&',
     'G5 需 totalCount≥2', A_TESTS),

    # ── B: validateGenuiComponent（11 个分支判据）──
    ('B1 diff-after', B_SRC,
     "raw['before'] is String && raw['after'] is String;",
     "raw['before'] is String;",
     'diff 必须含 after', B_TESTS),
    ('B2 quiz-options', B_SRC,
     "(m['options'] as List).length < 2",
     "(m['options'] as List).length < 1",
     'quiz options ≥2', B_TESTS),
    ('B3 quiz-answer', B_SRC,
     "if (m['answer'] is! int) return false;",
     "if (m['answer'] is! num) return false;",
     'quiz answer 必须是 int', B_TESTS),
    ('B4 stat-label', B_SRC,
     STAT_BLOCK,
     STAT_BLOCK.replace("m['label'] is! String", "m['label'] is! Object?"),
     'stat 必须含 label', B_TESTS),
    ('B5 stat-value', B_SRC,
     STAT_BLOCK,
     STAT_BLOCK.replace("m['value'] is! num", "m['value'] is! Object?"),
     'stat 必须含 value', B_TESTS),
    ('B6 stat-max', B_SRC,
     STAT_BLOCK,
     STAT_BLOCK.replace("m['max'] is! num", "m['max'] is! Object?"),
     'stat 必须含 max', B_TESTS),
    ('B7 progress-label', B_SRC,
     PROGRESS_BLOCK,
     PROGRESS_BLOCK.replace("m['label'] is! String", "m['label'] is! Object?"),
     'progress 必须含 label', B_TESTS),
    ('B8 progress-status', B_SRC,
     PROGRESS_BLOCK,
     PROGRESS_BLOCK.replace("m['status'] is! String",
                            "m['status'] is! Object?"),
     'progress 必须含 status', B_TESTS),
    ('B9 timeline-date', B_SRC,
     TIMELINE_BLOCK,
     TIMELINE_BLOCK.replace("m['date'] is! String", "m['date'] is! Object?"),
     'timeline 必须含 date', B_TESTS),
    ('B10 timeline-title', B_SRC,
     TIMELINE_BLOCK,
     TIMELINE_BLOCK.replace("m['title'] is! String", "m['title'] is! Object?"),
     'timeline 必须含 title', B_TESTS),
    # 白名单检查与 switch 兜底互为纵深防御：单点破坏其一，另一仍拒收
    # 未知类型 → 单点变异等价（V4.16），故按契约做**双点**变异：
    # 同时放行白名单检查与 switch 兜底，未知类型若被接受即为契约破防。
    ('B11 whitelist', B_SRC,
     [('if (!kGenuiWhitelist.contains(type)) return null;',
       'if (false) return null;'),
      ('    _ => false,', '    _ => true,')],
     None,
     '白名单外类型必须拒收（白名单检查 + switch 兜底双重防线）', B_TESTS),
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
    print('批次 F 分支级判据覆盖复检（V4.21）')
    print('拦住 = 该分支有断言锚定；漏网 = 该分支虚覆盖，重构前须补测')
    print('=' * 70)

    base_cache = {}
    results = []
    try:
        for mid, src, old, new, why, tests in MUTATIONS:
            original = cache[src]
            eol = detect_eol(original)
            # old/new 支持字符串（单点变异）或 [(o, n), ...]（多点变异）
            raw_pairs = old if isinstance(old, list) else [(old, new)]
            pairs = [(adapt_eol(o, eol), adapt_eol(n, eol))
                     for o, n in raw_pairs]

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

            # 逐点校验 + 顺序替换（后一个锚点在前一个替换后的文本上计数）
            mutated = original
            anchor_err = None
            for o_a, n_a in pairs:
                if o_a not in mutated:
                    anchor_err = '锚点缺失（%r）' % o_a[:70]
                    break
                if mutated.count(o_a) != 1:
                    anchor_err = '锚点不唯一（%d 次：%r）' % (
                        mutated.count(o_a), o_a[:50])
                    break
                mutated = mutated.replace(o_a, n_a, 1)
            if anchor_err:
                print('\n[%s] INJECT-FAILED：%s' % (mid, anchor_err))
                results.append((mid, why, '锚点异常'))
                continue

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
    print('合计 %d：真覆盖 %d / 虚覆盖 %d / 异常 %d'
          % (len(results), n_real, n_virt, n_bad))
    if n_virt:
        print('\n虚覆盖分支（重构前须补测）：')
        for mid, why, v in results:
            if v == '虚覆盖':
                print('  - [%s] %s' % (mid, why))
    return 0 if (same and n_bad == 0) else 1


if __name__ == '__main__':
    sys.exit(main())
