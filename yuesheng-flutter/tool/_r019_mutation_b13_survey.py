# -*- coding: utf-8 -*-
"""批次十三 _sendMessageCore 变异摸底（拆前确认覆盖，V4.20 方法论）。"""
import io
import os
import subprocess

MUTATIONS = [
    (
        'lib/services/chat_service.dart',
        'test/services/chat_service_send_message_test.dart',
        [
            (
                'B1 teaching state 读取反转 ts!=null -> ts==null',
                '      if (ts != null) {',
                '      if (ts == null) {',
            ),
            (
                'B2 isBeginner 判定 && -> ||',
                '            level != BeginnerLevel.n4Independent.value &&',
                '            level != BeginnerLevel.n4Independent.value ||',
            ),
            (
                'B3 发送时间记录删除（_lastUserSendAtSec 不更新）',
                '    _lastUserSendAtSec[sessionId] = nowAtSec;',
                '    // 变异：不更新发送时间',
            ),
            (
                'B4 预算闸门 triggered 反转',
                '    if (guardReport.triggered) {',
                '    if (!guardReport.triggered) {',
            ),
            (
                'B5 PHI 素材提示 dropped 反转',
                '    if (guardReport.dropped) {',
                '    if (!guardReport.dropped) {',
            ),
            (
                'B6 诊断 only 传值反转（handler 收到相反值）',
                '      diagnosisOnly: diagnosisOnly,',
                '      diagnosisOnly: !diagnosisOnly,',
            ),
            (
                'B7 取消判定 || -> &&',
                '        e is LlmRequestCancelledException ||',
                '        e is LlmRequestCancelledException &&',
            ),
        ],
    ),
]


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def run_test(test_file):
    env = dict(os.environ)
    env.pop('HTTP_PROXY', None)
    env.pop('HTTPS_PROXY', None)
    r = subprocess.run(
        f'flutter test {test_file} --no-pub',
        capture_output=True, text=True, timeout=300, shell=True, env=env,
    )
    return r.stdout + r.stderr


for src, test, cases in MUTATIONS:
    orig = read(src)
    try:
        for name, anchor, mutated in cases:
            t = read(src)
            if anchor not in t:
                print(f'INJECT-FAILED {name}: 锚点缺失')
                continue
            write(src, t.replace(anchor, mutated, 1))
            out = run_test(test)
            leaked = 'All tests passed!' in out
            print(f'[{"漏网" if leaked else "拦截"}] {name}')
            if leaked:
                print('  --- 输出尾部 ---')
                print('\n'.join(out.splitlines()[-4:]))
            write(src, t)
    finally:
        write(src, orig)

print('摸底完成')
