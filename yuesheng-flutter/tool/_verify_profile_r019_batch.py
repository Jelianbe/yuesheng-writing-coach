# -*- coding: utf-8 -*-
"""验证 student_profile 家族 R-019 重构「被现有测试兜住」（V4.15）。

背景：这三个函数（inferCognitiveStyle / buildStrategyEffectiveness /
inferProficiency）在 test/ 里**零直接引用**，只有经 buildStudentContext 的
间接覆盖。间接测试全绿不足以证明重构安全——必须证明测试拦得住行为变化。
若变异漏网，说明覆盖是虚的，应先补测试再重构（或登记为已知风险）。

判据按 V4.16：必须判定该行带 flutter test 的失败标记 [E]。
按 V4.18：跑 flutter test 必须清空会话代理，且先做基线健康校验——
加载失败的行同样带 [E]，会让「拦截成功」假绿。
"""
import io
import os
import shutil
import subprocess
import sys

TESTS = [
    'test/services/student_profile_infer_test.dart',
    'test/services/student_profile_c71_test.dart',
    'test/services/style_profile_pipeline_test.dart',
    'test/services/skill_prompt_anchor_test.dart',
]

FLUTTER = (
    shutil.which('flutter.bat')
    or shutil.which('flutter')
    or r'D:\flutter\bin\flutter.bat'
)

# (说明, 源文件, 原文本, 变异文本)
MUTATIONS = [
    ('A 认知风格：早退阈值 <2 → <1（单条消息也推断）',
     'lib/services/student_profile.dart',
     'if (userMessages.length < 2) return null;',
     'if (userMessages.length < 1) return null;'),
    ('B 认知风格：analytical 判据 >= → >（边界翻转）',
     'lib/services/student_profile.dart',
     'if (ratio >= CognitiveStyleThresholds.analyticalRatio) {',
     'if (ratio > CognitiveStyleThresholds.analyticalRatio) {'),
    ('C 策略效果：去掉「非 no_change 覆盖既有值」',
     'lib/services/student_profile.dart',
     "        if (eff != 'no_change') existing.eff = eff;",
     '        if (eff == "no_change") existing.eff = eff;'),
    ('D 策略效果：样本门槛 <2 → <1',
     'lib/services/student_profile.dart',
     "if (modeRecords.length < 2) return '';",
     "if (modeRecords.length < 1) return '';"),
    ('E 能力等级：l3 阈值 >= → >（边界翻转）',
     'lib/services/student_profile_compute.dart',
     'if (l3Count >= ProficiencyThresholds.beginnerL3CountThreshold) {',
     'if (l3Count > ProficiencyThresholds.beginnerL3CountThreshold) {'),
    ('F 能力等级：l2 阈值 >= → >（边界翻转）',
     'lib/services/student_profile_compute.dart',
     'if (l2Count >= ProficiencyThresholds.beginnerL2CountThreshold) {',
     'if (l2Count > ProficiencyThresholds.beginnerL2CountThreshold) {'),
]


def run_tests():
    env = dict(os.environ)
    for k in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy'):
        env.pop(k, None)
    env['NO_PROXY'] = 'localhost,127.0.0.1'
    r = subprocess.run([FLUTTER, 'test'] + TESTS, env=env,
                       capture_output=True, text=True)
    return (r.stdout or '') + (r.stderr or '')


def main():
    cache = {}
    for _, src, _, _ in MUTATIONS:
        if src not in cache:
            with io.open(src, encoding='utf-8', newline='') as f:
                cache[src] = f.read()

    base_out = run_tests()
    if 'All tests passed' not in base_out:
        print('ABORT：基线测试未全绿（环境问题），判据不可信')
        print(base_out[-600:])
        return 2
    print('基线健康：All tests passed ✓\n')

    results = []
    try:
        for name, src, old, new in MUTATIONS:
            original = cache[src]
            if old not in original:
                print('INJECT-FAILED: %s —— 锚点未找到（源码未改动）' % name)
                print('  锚点: %r' % old[:70])
                results.append((name, False))
                continue
            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(original.replace(old, new, 1))
            try:
                out = run_tests()
                caught = any('[E]' in line for line in out.splitlines())
                print('%s\n   → %s'
                      % (name, '拦截成功' if caught else '❌ 漏网'))
                results.append((name, caught))
            finally:
                with io.open(src, 'w', encoding='utf-8', newline='') as f:
                    f.write(original)
    finally:
        for src, content in cache.items():
            with io.open(src, 'w', encoding='utf-8', newline='') as f:
                f.write(content)
        print('\n[源码已恢复]')

    same = all(io.open(s, encoding='utf-8', newline='').read() == c
               for s, c in cache.items())
    print('恢复字节一致：%s' % same)
    clean = 'All tests passed' in run_tests()
    print('恢复后测试：%s' % ('全绿' if clean else '❌ 仍有失败'))

    print('\n===== 汇总 =====')
    for name, ok in results:
        print('  %-48s %s' % (name, '✅' if ok else '❌ 漏网（覆盖不足）'))
    return 0 if (same and clean and all(ok for _, ok in results)) else 1


if __name__ == '__main__':
    sys.exit(main())
