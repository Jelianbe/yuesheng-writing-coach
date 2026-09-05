# -*- coding: utf-8 -*-
"""K-9 M5 盲区补测的变异验证（一次性，仿 _c69_mutation.py 范式）。

M5 变异：_resolveFinalAssistantContent 兜底分支 `if (c > 0)` → `if (c < 0)`。
期望：test #1（有实体 → 判真不 abort）必须失败 → 变异被拦截。
try/finally 恢复 + 注入前锚点校验（INJECT-FAILED 显式报出）。
"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / 'lib' / 'services' / 'diagnosis_flow_handler.dart'
TEST = ROOT / 'test' / 'services' / 'diagnosis_flow_outline_fallback_test.dart'
ANCHOR = 'if (c > 0) treatAsValid = true;'
MUTATED = 'if (c < 0) treatAsValid = true;'


def _flutter_cmd():
    for cand in ['flutter', 'flutter.bat']:
        p = shutil.which(cand)
        if p:
            return p
    raise RuntimeError('找不到 flutter 可执行文件')


FLUTTER = _flutter_cmd()

t = io.open(SRC, encoding='utf-8', newline='').read()
eol = '\r\n' if t.count('\r\n') >= t.count('\n') / 2 else '\n'

if ANCHOR not in t:
    print('INJECT-FAILED: 锚点未找到（工作区行尾/内容可能已变）')
    sys.exit(2)

mutated = t.replace(ANCHOR, MUTATED, 1)
try:
    io.open(SRC, 'w', encoding='utf-8', newline='').write(mutated)
    r = subprocess.run(
        [FLUTTER, 'test', str(TEST), '--no-pub'],
        cwd=str(ROOT), capture_output=True, text=True, timeout=300,
        encoding='utf-8', errors='replace', shell=False,
    )
    out = r.stdout + r.stderr
    passed = 'All tests passed!' in out
    if passed:
        print('M5-MUTATION: 漏网（测试仍全绿，变异未被拦截）')
        sys.exit(1)
    print('M5-MUTATION: 拦截 ✓（测试失败，变异被 #1 判据抓住）')
    # 打印失败摘要（几行）
    for line in out.splitlines():
        if '[E]' in line or 'FAILED' in line.upper() or 'Expected' in line or 'reason' in line.lower():
            print('  |', line.strip()[:120])
finally:
    io.open(SRC, 'w', encoding='utf-8', newline='').write(t)
    print('已恢复原文件')
