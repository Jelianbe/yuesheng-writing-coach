# -*- coding: utf-8 -*-
"""验证新增的 3 例 token_budget_guard 测试「能失败」（V4.15）。

只绿不红的护栏没有意义。三个变异各自对应一个新用例：
  A 索引剔除错位      → 应被「裁剪剔除的是被裁阶段的索引」抓到
  B <= 改成 <         → 应被「恰好等于 maxBudget 走 no-op」抓到
  C 去掉中途 break    → 应被「中途达标即停」抓到

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失显式报错 + 收尾 git diff 复核。
按 V4.4 延伸：工作区 CRLF，读写 newline=''，锚点一律 CRLF。
"""
import io
import shutil
import subprocess
import sys

SRC = 'lib/services/token_budget_guard.dart'
TEST = 'test/services/token_budget_guard_test.dart'

MUTATIONS = [
    ('A 索引剔除错位（toRemove.contains(i) → i + 1）',
     'if (toRemove.contains(i)) continue;\r\n      kept.add(messages[i]);',
     'if (toRemove.contains(i + 1)) continue;\r\n      kept.add(messages[i]);',
     '裁剪剔除的是被裁阶段的索引'),
    ('B no-op 分支的 totalAfter 清零',
     'totalBefore: total,\r\n        totalAfter: total,',
     'totalBefore: total,\r\n        totalAfter: 0,',
     '边界：总量恰好等于 maxBudget'),
    ('C 去掉中途达标即停的 break',
     'for (final stage in TokenBudgetTable.planDegradation()) {\r\n'
     '      if (current <= maxBudget) break;\r\n',
     'for (final stage in TokenBudgetTable.planDegradation()) {\r\n',
     '中途达标即停：更低优先级阶段完整保留'),
]


# Windows 原生 python 的 PATH 里没有 flutter（Git Bash 有），必须显式解析。
# V4.10 踩过的坑：subprocess 找不到可执行文件会抛异常，若此时缺 finally
# 恢复，被变异的源码就永久留在磁盘上了。
FLUTTER = (
    shutil.which('flutter.bat')
    or shutil.which('flutter')
    or r'D:\flutter\bin\flutter.bat'
)


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
                print('INJECT-FAILED: %s —— 锚点未找到' % name)
                results.append((name, False))
                continue
            with io.open(SRC, 'w', encoding='utf-8', newline='') as f:
                f.write(original.replace(old, new, 1))
            try:
                out = run_test()
                # 判据：该用例所在行必须带 flutter test 的失败标记 [E]。
                # 不能只判「用例名出现过」——通过和失败都会打印用例名（V4.7
                # 假判据的重演：那样判据恒为真，等于没判）。
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

    out = run_test()
    clean = 'All tests passed' in out
    print('恢复后测试：%s' % ('全绿' if clean else '❌ 仍有失败'))

    print('\n===== 汇总 =====')
    for name, ok in results:
        print('  %-44s %s' % (name, '✅' if ok else '❌ 漏网'))
    return 0 if (same and clean and all(ok for _, ok in results)) else 1


if __name__ == '__main__':
    sys.exit(main())
