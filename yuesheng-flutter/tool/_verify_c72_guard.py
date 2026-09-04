# -*- coding: utf-8 -*-
"""验证 ADR-C72 护栏测试「能失败」（V4.15）。

护栏防的是「唯一例外」被后续批次删掉或改残：三处交叉引用 + 激活块判据锚文本。
补完护栏后必须证明它拦得住破坏，否则只是装饰。

四个变异各自对应一条断言：
  A 删掉撞车裁决第三行整行 → 「撞车裁决第三行存在且判据完整」
  B 去掉 §7.3 的唯一例外指引 → 「三处唯一例外交叉引用」（计数 3→2）
  C 第三行删掉 N0 铁律句   → 「例外不放松 N0 铁律」
  D 改残激活字段引号形态   → 「撞车裁决第三行存在且判据完整」

按 V4.10：改源码做验证必须 try/finally 恢复 + 锚点缺失显式报错。
按 V4.16：判据必须带 flutter test 的失败标记 [E]，不能只判「用例名出现过」。
按 V4.18：跑 flutter test 必须清空会话代理环境变量——否则 Dart VM 连
    flutter_tester 的 localhost WebSocket 被代理吃掉，报
    "Invalid WebSocket upgrade request"。这个故障很阴险：加载失败的行同样
    带 [E]，会让「拦截成功」判据假绿。故先做基线健康校验，基线不绿直接 abort。
"""
import io
import os
import shutil
import subprocess
import sys

SRC = 'lib/services/skills_l1_core_p2.dart'
TEST = 'test/services/l1_zero_basis_activation_guard_test.dart'

# Windows 原生 python 的 PATH 里没有 flutter（Git Bash 有），必须显式解析
FLUTTER = (
    shutil.which('flutter.bat')
    or shutil.which('flutter')
    or r'D:\flutter\bin\flutter.bat'
)

MUTATIONS = [
    ('A 删掉撞车裁决第三行整行',
     '- 疑似零基础学员首次出现（学员说「从没写过」「不知道怎么写」等，且尚无任何文本）：'
     '**仍附最小激活块**',
     '- 疑似零基础学员首次出现（学员说「从没写过」「不知道怎么写」等）：',
     '撞车裁决第三行存在且判据完整'),
    ('B 去掉 §7.3 的唯一例外指引',
     '- ✅ 从零构建模式下，诊断引擎不启动（用户还没有可诊断的内容）。唯一例外：',
     '- ✅ 从零构建模式下，诊断引擎不启动（用户还没有可诊断的内容）。',
     '三处「唯一例外」交叉引用'),
    ('C 第三行删掉 N0 铁律句',
     '。自然语言部分照常按 N0 铁律：不诊断、不评判、不给技法提示。',
     '。',
     '例外不放松 N0 铁律'),
    ('D 改残激活字段引号形态',
     '只填 `suggested_beginner_level: "N0_ENGAGE"` 激活零基础路径',
     '只填 `suggested_beginner_level: N0_ENGAGE` 激活零基础路径',
     '撞车裁决第三行存在且判据完整'),
]


def run_test():
    env = dict(os.environ)
    # V4.18：清空代理，否则 flutter_tester 的 localhost WebSocket 握手失败
    for k in ('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy'):
        env.pop(k, None)
    env['NO_PROXY'] = 'localhost,127.0.0.1'
    r = subprocess.run([FLUTTER, 'test', TEST], env=env,
                       capture_output=True, text=True)
    return (r.stdout or '') + (r.stderr or '')


def caught(out, expect_fail):
    """判据：目标用例所在行必须带 flutter test 的失败标记 [E]（V4.16）。"""
    return any(expect_fail in line and '[E]' in line
               for line in out.splitlines())


def main():
    with io.open(SRC, encoding='utf-8', newline='') as f:
        original = f.read()
    # 行尾自适应（V4.17 延伸：本文件入库即 LF）
    eol = '\r\n' if original.count('\r\n') >= original.count('\n') / 2 else '\n'
    print('源码行尾: %s' % ('CRLF' if eol == '\r\n' else 'LF'))

    # 基线健康校验：环境挂了会让下面的判据假绿，必须先确认基线全绿
    base_out = run_test()
    if 'All tests passed' not in base_out:
        print('ABORT：基线测试未全绿，环境问题（非变异所致），判据不可信')
        print(base_out[-500:])
        return 2
    print('基线健康：All tests passed ✓\n')

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
                ok = caught(out, expect_fail)
                print('%s\n   应被「%s」拦截 → %s'
                      % (name, expect_fail, '拦截成功' if ok else '❌ 漏网'))
                results.append((name, ok))
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
        print('  %-32s %s' % (name, '✅' if ok else '❌ 漏网'))
    return 0 if (same and clean and all(ok for _, ok in results)) else 1


if __name__ == '__main__':
    sys.exit(main())
