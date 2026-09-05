# -*- coding: utf-8 -*-
"""R-019 批次（guardStream / suggestAttitudeAdjustment / loadSyndromeTrends）拆分后的判据级变异验证。

对每个函数打 2-3 个判据变异，跑对应测试文件，期望全部被拦截（测试失败）。
try/finally 恢复 + 注入前锚点校验（INJECT-FAILED 显式报出，不静默 continue）。
"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

# (源文件, 测试文件, [(变异名, 锚点, 变异后)])
MUTATIONS = [
    # guardStream
    ('lib/services/stream_guard.dart', 'test/stream_guard_test.dart', [
        ('M1 首字前后计时切换失效',
         'timer = Timer(firstReceived ? idle : connect, () {',
         'timer = Timer(idle, () {'),
        ('M2 首字后错误文案失效',
         "      ? '模型响应中断（超过 ${idle.inSeconds} 秒未收到新内容）'",
         "      ? '模型响应超时（超过 ${connect.inSeconds} 秒未返回首个字符）'"),
        ('M3 首字标记失效',
         '      if (!firstReceived) firstReceived = true;',
         '      firstReceived = true;'),
    ]),
    # suggestAttitudeAdjustment
    ('lib/services/attitude_advisor.dart', 'test/services/attitude_advisor_test.dart', [
        ('M1 冷却期反转',
         '            AttitudeThresholds.suggestionCooldownMs;',
         '            AttitudeThresholds.suggestionCooldownMs - 1;'),
        ('M2 升级非最高档边界失效',
         '  if (currentIndex >= attitudeOrder.length - 1) return null;',
         '  if (currentIndex > attitudeOrder.length - 1) return null;'),
        ('M3 降级阈值边界失效',
         '      (avgSeverity <= AttitudeThresholds.downgradeSeverityThreshold &&',
         '      (avgSeverity < AttitudeThresholds.downgradeSeverityThreshold &&'),
    ]),
    # loadSyndromeTrends
    ('lib/services/syndrome_tracker.dart', 'test/services/syndrome_tracker_test.dart', [
        ('M1 空 syndrome_id 过滤反转',
         '        if (id.isEmpty) continue;',
         '        if (id.isNotEmpty) continue;'),
        ('M2 窗口 5 条边界失效',
         '      final recent = points.length > 5',
         '      final recent = points.length >= 5'),
        ('M3 排序反转',
         '      return b.occurrenceCount - a.occurrenceCount;',
         '      return a.occurrenceCount - b.occurrenceCount;'),
    ]),
]


def _flutter_cmd():
    for cand in ['flutter', 'flutter.bat']:
        p = shutil.which(cand)
        if p:
            return p
    raise RuntimeError('找不到 flutter 可执行文件')


FLUTTER = _flutter_cmd()

total = 0
failed = []
for src_rel, test_rel, cases in MUTATIONS:
    src = ROOT / src_rel
    test = ROOT / test_rel
    orig = io.open(src, encoding='utf-8', newline='').read()
    eol = '\r\n' if orig.count('\r\n') >= orig.count('\n') / 2 else '\n'

    for name, anchor, mutated in cases:
        a = anchor.replace('\n', eol)
        m = mutated.replace('\n', eol)
        if a not in orig:
            print('INJECT-FAILED: [{}] 锚点未找到: {}'.format(name, src_rel))
            failed.append((name, '锚点缺失'))
            continue
        total += 1
        tmp = orig.replace(a, m, 1)
        try:
            io.open(src, 'w', encoding='utf-8', newline='').write(tmp)
            r = subprocess.run(
                [FLUTTER, 'test', str(test), '--no-pub'],
                cwd=str(ROOT), capture_output=True, text=True, timeout=300,
                encoding='utf-8', errors='replace', shell=False,
            )
            out = r.stdout + r.stderr
            if 'All tests passed!' in out:
                print('MUTATION-LOOSE: [{}] 漏网（测试仍全绿）'.format(name))
                failed.append((name, '漏网'))
            else:
                print('MUTATION-KILL: [{}] 拦截 ✓'.format(name))
        finally:
            io.open(src, 'w', encoding='utf-8', newline='').write(orig)

print()
print('变异总数: {}, 未拦截: {}'.format(total, len(failed)))
if failed:
    for n, why in failed:
        print('  FAIL: {} — {}'.format(n, why))
    sys.exit(1)
print('全部变异被拦截 ✓')
