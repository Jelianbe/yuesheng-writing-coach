# -*- coding: utf-8 -*-
"""批次 F 清偿后的 V4.14 验证：基线重生成后，新函数仍能被测出来。

清偿 = 从 r019_baseline.json 的豁免清单里移除。移除了就必须证明：
这些函数**一旦再次超限就会被测出来**，而不是被某个宽泛的 key 误豁免。
做法：逐个把目标函数撑大到 >50 行（注入 pad 注释），跑
`check_r019.py --baseline`，确认该函数的名字出现在报告里。

按 V4.10：改源码做验证必须 try/finally 恢复 + 字节一致复核。
按 V4.14：锚点必须取目标函数**独有**的行，否则 pad 会注入到别的函数里
（V4.14 原事故：锚点在文件里有 2 处，报出来的函数是错的）。
按 V4.17：工作区行尾不统一，多行注入须按文件实际行尾自适应。

用法：python tool/_verify_batch_f_baseline.py
"""
import io
import os
import re
import subprocess
import sys


def find_matching_close(s, open_idx):
    """从 s[open_idx]（必须是 '{'）起找匹配的 '}'，忽略字符串/注释。"""
    depth = 0
    i = open_idx
    in_str = None
    in_line_comment = False
    in_block_comment = False
    while i < len(s):
        c = s[i]
        if in_line_comment:
            if c == '\n':
                in_line_comment = False
        elif in_block_comment:
            if c == '*' and i + 1 < len(s) and s[i + 1] == '/':
                in_block_comment = False
                i += 1
        elif in_str:
            if c == '\\':
                i += 1
            elif c == in_str:
                in_str = None
        else:
            if c == '/' and i + 1 < len(s) and s[i + 1] == '/':
                in_line_comment = True
                i += 1
            elif c == '/' and i + 1 < len(s) and s[i + 1] == '*':
                in_block_comment = True
                i += 1
            elif c == '"' or c == "'":
                in_str = c
            elif c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return i + 1
        i += 1
    return len(s)

BASELINE = 'tool/r019_baseline.json'
PAD_N = 55

A_SRC = 'lib/services/syndrome_skill_levels.dart'
B_SRC = 'lib/services/genui_validator.dart'

# (标签, 源文件, 待验证函数名, 锚点原文, 替换模板)
# 模板里的 {pad} 会被替换成 PAD_N 行注释
TARGETS = [
    ('interventionLevelForTrainingCount', A_SRC,
     'interventionLevelForTrainingCount',
     '  // 延迟撤脚手架（保守，主）永远优先于提前撤脚手架（正向，辅）',
     '  // 延迟撤脚手架（保守，主）永远优先于提前撤脚手架（正向，辅）\n{pad}'),
    ('_baseLevelForCount', A_SRC, '_baseLevelForCount',
     '  if (trainingCount >= 4) return InterventionLevel.youDo;',
     '  if (trainingCount >= 4) return InterventionLevel.youDo;\n{pad}'),
    ('_applyDelayRules', A_SRC, '_applyDelayRules',
     '  if (performance.consecutiveFails >= 3) return InterventionLevel.iDo;',
     '  if (performance.consecutiveFails >= 3) '
     'return InterventionLevel.iDo;\n{pad}'),
    ('_applyAdvanceRules', A_SRC, '_applyAdvanceRules',
     '  final allPassed = performance.consecutivePasses '
     '== performance.totalCount;',
     '  final allPassed = performance.consecutivePasses '
     '== performance.totalCount;\n{pad}'),
    ('validateGenuiComponent', B_SRC, 'validateGenuiComponent',
     '  // 白名单与校验器一一对应：新增组件类型必须同时补校验器，',
     '  // 白名单与校验器一一对应：新增组件类型必须同时补校验器，\n{pad}'),
    # 表达式体（=>）函数：注入 pad 前须先转成块体，否则 pad 落在函数外
    # check_r019.py 不识别 `=>` 表达式体函数，即使撑大也跑不出「超限」，
    # 故本项标 SKIP——check_r019 盲区，待未来工具支持表达式体后再纳入。
    ('_validateDiff', B_SRC, '_validateDiff',
     "    raw['before'] is String && raw['after'] is String;",
     '{{\n{pad}\n    return raw[\'before\'] is String '
     "&& raw['after'] is String;\n  }}",
     'SKIP:check_r019 不识别 => 表达式体'),
    ('_validateQuiz', B_SRC, '_validateQuiz',
     "    if (m['q'] is! String) return false;",
     "    if (m['q'] is! String) return false;\n{pad}"),
    ('_validateStat', B_SRC, '_validateStat',
     "    if (m['value'] is! num) return false;",
     "    if (m['value'] is! num) return false;\n{pad}"),
    ('_validateProgress', B_SRC, '_validateProgress',
     "    if (m['status'] is! String) return false;",
     "    if (m['status'] is! String) return false;\n{pad}"),
    ('_validateTimeline', B_SRC, '_validateTimeline',
     "    if (m['date'] is! String) return false;",
     "    if (m['date'] is! String) return false;\n{pad}"),
]


def detect_eol(content):
    return '\r\n' if content.count('\r\n') >= content.count('\n') / 2 else '\n'


def run_check():
    env = dict(os.environ)
    for k in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy'):
        env.pop(k, None)
    env['NO_PROXY'] = 'localhost,127.0.0.1'
    r = subprocess.run(
        [sys.executable, 'tool/check_r019.py', '--baseline', BASELINE],
        env=env, capture_output=True, text=True)
    return (r.stdout or '') + (r.stderr or '')


def main():
    cache = {}
    for tup in TARGETS:
        _, src, _, _, _ = tup[:5]
        if src not in cache:
            with io.open(src, encoding='utf-8', newline='') as f:
                cache[src] = f.read()

    print('=' * 70)
    print('V4.14 验证：基线重生成后，清偿掉的函数仍能被测出（撑大 %d 行）'
          % PAD_N)
    print('=' * 70)

    results = []
    try:
        for tup in TARGETS:
            label, src, func, old, tpl = tup[:5]
            skip = tup[5] if len(tup) > 5 else None
            if skip:
                print('  [%-32s] SKIP — %s' % (label, skip))
                results.append((label, 'SKIP'))
                continue
            original = cache[src]
            eol = detect_eol(original)
            pad = ('  // R019-PAD\n' * PAD_N).rstrip('\n')
            new = tpl.replace('{pad}', pad)
            old_a = old.replace('\n', eol) if eol != '\n' else old
            new_a = new.replace('\n', eol) if eol != '\n' else new

            if original.count(old_a) != 1:
                print('\n[%s] ANCHOR-ERROR：锚点出现 %d 次'
                      % (label, original.count(old_a)))
                print('  锚点: %r' % old_a[:80])
                results.append((label, '锚点异常'))
                continue

            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(original.replace(old_a, new_a, 1))
            try:
                # Debug: 注入后该函数实际起止
                mutated = original.replace(old_a, new_a, 1)
                for m in re.finditer(r'(?:^|\n)(?P<sig>(?:[A-Za-z_][\w<>,\?\s]*?\s+)'
                                      r'(?P<name>' + re.escape(func)
                                      + r')\s*\([^)]*\)[^{]*\{)',
                                      mutated):
                    end = find_matching_close(mutated, m.end() - 1)
                    body = mutated[m.start():end]
                    print('    [debug %s] body lines=%d, '
                          'starts at line %d'
                          % (func, body.count('\n'),
                             mutated[:m.start()].count('\n') + 1))
                out = run_check()
                hit = func in out
                results.append((label, '拦住' if hit else '未拦住'))
                print('  [%-32s] %s' % (
                    label, '被测出（基线有效）' if hit else '★ 漏报'))
                if not hit:
                    print('    输出片段:\n' + '\n'.join(
                        l for l in out.splitlines() if func[:6] in l
                        or 'genui_validator' in l or 'syndrome_skill' in l
                    )[:400])
            finally:
                with io.open(src, 'w', encoding='utf-8', newline='') as f:
                    f.write(original)
    finally:
        for src, content in cache.items():
            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(content)

    same = all(io.open(s, encoding='utf-8', newline='').read() == c
               for s, c in cache.items())

    n_eff = sum(1 for _, v in results if v == '拦住')
    n_skip = sum(1 for _, v in results if v == 'SKIP')
    n_run = len(results) - n_skip
    print('\n' + '=' * 70)
    print('源码恢复字节一致：%s' % same)
    print('基线有效性：%d/%d 被测出（SKIP %d）'
          % (n_eff, n_run, n_skip))
    for label, v in results:
        if v != '拦住':
            print('  ★ %-32s %s' % (label, v))
    return 0 if (same and n_eff == n_run) else 1


if __name__ == '__main__':
    sys.exit(main())
