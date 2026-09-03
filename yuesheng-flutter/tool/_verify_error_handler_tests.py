# -*- coding: utf-8 -*-
"""验证新增的 A12 脱敏测试「能失败」（V4.15）。

脱敏防的是 API Key 经 error_logs / UI 泄漏（宪法 §八），但此前**零测试覆盖**——
从来没人验证过它真的生效。补完测试后必须证明这些测试拦得住破坏。

三个变异各自对应一条断言：
  A 删掉 Bearer 正则        → 应被 #5 的 message 断言抓到
  B 删掉 api_key 正则       → 应被 #5 的 stack 断言抓到
  C 去掉 stack 的 null 保护 → 应被 #6 的 stack isNull 抓到
     （stack 会被 coerce 成 '' 而非 NULL，正是源码注释警告的那件事）

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失显式报错 + 收尾 git diff 复核。
按 V4.4 延伸：工作区 CRLF，读写 newline=''，锚点一律 CRLF。
判据按 V4.16：必须判定该行带 flutter test 的失败标记 [E]，
不能只判「用例名出现过」——通过和失败都会打印用例名。
"""
import shutil
import io
import subprocess
import sys

SRC = 'lib/services/error_handler.dart'
TEST = 'test/services/error_handler_test.dart'

# Windows 原生 python 的 PATH 里没有 flutter（Git Bash 有），必须显式解析
FLUTTER = (
    shutil.which('flutter.bat')
    or shutil.which('flutter')
    or r'D:\flutter\bin\flutter.bat'
)

MUTATIONS = [
    ('A 删掉 Bearer 脱敏正则',
     "      RegExp(r'(Bearer\\s+)[A-Za-z0-9._\\-]+', caseSensitive: false),\r\n",
     '',
     '#5 A12 安全红线'),
    ('B 删掉 api_key 脱敏正则',
     "      RegExp(r'(api[_-]?key\\s*[:=]\\s*)[^\\s\",}\\]]+', caseSensitive: false),\r\n",
     '',
     '#5 A12 安全红线'),
    ('C 去掉 stack 的 null 保护（会被 coerce 成空串）',
     '      stack: stack == null ? null : _redactSensitive(stack),',
     '      stack: _redactSensitive(stack),',
     '#6 A12：context 为 null'),
]


def run_test():
    r = subprocess.run([FLUTTER, 'test', TEST],
                       capture_output=True, text=True)
    return (r.stdout or '') + (r.stderr or '')


def main():
    with io.open(SRC, encoding='utf-8', newline='') as f:
        original = f.read()

    results = []
    try:
        for name, old, new, expect_fail in MUTATIONS:
            if old not in original:
                print('INJECT-FAILED: %s —— 锚点未找到（源码未改动）' % name)
                print('  锚点: %r' % old[:70])
                results.append((name, False))
                continue
            with io.open(SRC, 'w', encoding='utf-8', newline='') as f:
                f.write(original.replace(old, new, 1))
            try:
                out = run_test()
                caught = any(
                    expect_fail in line and '[E]' in line
                    for line in out.splitlines()
                )
                print('%s\n   变异已注入 → 被「%s」拦截=%s  → %s'
                      % (name, expect_fail, caught,
                         '拦截成功' if caught else '❌ 漏网'))
                results.append((name, caught))
            finally:
                with io.open(SRC, 'w', encoding='utf-8', newline='') as f:
                    f.write(original)
    finally:
        with io.open(SRC, 'w', encoding='utf-8', newline='') as f:
            f.write(original)
        print('\n[源码已恢复]')

    with io.open(SRC, encoding='utf-8', newline='') as f:
        same = f.read() == original
    print('恢复字节一致：%s' % same)

    clean = 'All tests passed' in run_test()
    print('恢复后测试：%s' % ('全绿' if clean else '❌ 仍有失败'))

    print('\n===== 汇总 =====')
    for name, ok in results:
        print('  %-46s %s' % (name, '✅' if ok else '❌ 漏网'))
    return 0 if (same and clean and all(ok for _, ok in results)) else 1


if __name__ == '__main__':
    sys.exit(main())
