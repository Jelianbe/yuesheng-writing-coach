# -*- coding: utf-8 -*-
"""V4.14 验证：新基线（235 条，排除生成代码后）是否仍能拦住新增超限。

按 V4.10：改源码做验证的脚本必须 try/finally 恢复，且收尾人工 git diff 复核。
按 V4.4 延伸：工作区是 CRLF，读写一律 newline=''，锚点用 CRLF。
"""
import io
import subprocess
import sys

SRC = 'lib/providers/writing_providers.dart'
BASE = 'tool/r019_baseline.json'
ANCHOR = '  Future<void> loadChapter() async {\r\n'
PAD = ''.join('    // V4.14 验证用填充行 %d\r\n' % i for i in range(45))


def run(args):
    return subprocess.run(args, capture_output=True, text=True)


def main():
    with io.open(SRC, encoding='utf-8', newline='') as f:
        original = f.read()

    if ANCHOR not in original:
        print('INJECT-FAILED: 锚点未找到，脚本未做任何改动')
        return 2

    ok = False
    try:
        with io.open(SRC, 'w', encoding='utf-8', newline='') as f:
            f.write(original.replace(ANCHOR, ANCHOR + PAD, 1))

        r = run([sys.executable, 'tool/check_r019.py',
                 '--baseline', BASE])
        out = (r.stdout or '') + (r.stderr or '')
        print('--- 撑大后的止血模式输出 ---')
        print(out[-800:])
        print('退出码 = %d' % r.returncode)

        caught = r.returncode != 0 and 'loadChapter' in out
        baseline_ok = '存量 235 个豁免' in out
        print()
        print('判据1 新基线生效（存量显示 235）：%s' % ('通过' if baseline_ok else '失败'))
        print('判据2 撑大后被报出且退出码非 0：%s' % ('通过' if caught else '失败'))
        ok = caught and baseline_ok
    finally:
        with io.open(SRC, 'w', encoding='utf-8', newline='') as f:
            f.write(original)
        print('\n[已恢复源码]')

    # 收尾复核：恢复后必须与原文件字节一致
    with io.open(SRC, encoding='utf-8', newline='') as f:
        restored = f.read()
    print('恢复字节一致：%s' % (restored == original))

    r2 = run([sys.executable, 'tool/check_r019.py', '--baseline', BASE])
    print('恢复后止血模式退出码 = %d（应为 0）' % r2.returncode)
    if r2.returncode != 0 or restored != original:
        return 1
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
