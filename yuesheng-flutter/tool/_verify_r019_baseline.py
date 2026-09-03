# -*- coding: utf-8 -*-
"""V4.14 验证：重生成后的 R-019 基线是否仍能拦住「已清偿函数重新变长」。

用法：
    python tool/_verify_r019_baseline.py \
        --src lib/services/token_budget_guard.dart \
        --anchor "  static BudgetGuardReport apply(" \
        --func apply --pad 45

按 V4.10：改源码做验证的脚本必须 try/finally 恢复，且收尾人工 git diff 复核。
按 V4.4 延伸：工作区是 CRLF，读写一律 newline=''，锚点统一转 CRLF。
"""
import argparse
import io
import json
import os
import subprocess
import sys

BASE = 'tool/r019_baseline.json'


def run(args):
    return subprocess.run(args, capture_output=True, text=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True, help='要临时撑大的源码文件')
    ap.add_argument('--anchor', required=True,
                    help='注入锚点（以该行结尾的整行，用 \\n 书写即可）')
    ap.add_argument('--func', required=True, help='期望被报出的函数名')
    ap.add_argument('--pad', type=int, default=45, help='填充行数')
    ap.add_argument('--baseline', default=BASE)
    args = ap.parse_args()

    anchor = (args.anchor + '\n').replace('\n', '\r\n')
    pad = ''.join('    // V4.14 验证用填充行 %d\r\n' % i for i in range(args.pad))

    with io.open(args.src, encoding='utf-8', newline='') as f:
        original = f.read()

    if anchor not in original:
        print('INJECT-FAILED: 锚点未找到（源码未做任何改动）')
        print('  锚点: %r' % anchor)
        return 2

    with io.open(args.baseline, encoding='utf-8') as f:
        baseline_n = len(json.load(f)['violations'])

    ok = False
    try:
        with io.open(args.src, 'w', encoding='utf-8', newline='') as f:
            f.write(original.replace(anchor, anchor + pad, 1))

        r = run([sys.executable, 'tool/check_r019.py',
                 '--baseline', args.baseline])
        out = (r.stdout or '') + (r.stderr or '')
        print('--- 撑大后的止血模式输出 ---')
        print(out[-700:])
        print('退出码 = %d' % r.returncode)

        caught = r.returncode != 0 and args.func in out
        baseline_ok = ('存量 %d 个豁免' % baseline_n) in out
        print()
        print('判据1 新基线生效（存量显示 %d）：%s'
              % (baseline_n, '通过' if baseline_ok else '失败'))
        print('判据2 撑大后 %s 被报出且退出码非 0：%s'
              % (args.func, '通过' if caught else '失败'))
        ok = caught and baseline_ok
    finally:
        with io.open(args.src, 'w', encoding='utf-8', newline='') as f:
            f.write(original)
        print('\n[已恢复源码]')

    with io.open(args.src, encoding='utf-8', newline='') as f:
        restored = f.read()
    same = restored == original
    print('恢复字节一致：%s' % same)

    r2 = run([sys.executable, 'tool/check_r019.py', '--baseline', args.baseline])
    print('恢复后止血模式退出码 = %d（应为 0）' % r2.returncode)

    if not same or r2.returncode != 0:
        return 1
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
