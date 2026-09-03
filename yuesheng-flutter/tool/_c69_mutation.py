# -*- coding: utf-8 -*-
"""ADR-C69 护栏变异验证：逐个注入变异 → 跑测试 → 恢复 → 记录哪条断言失败。

用法: python tool/_c69_mutation.py

硬要求（AGENTS.md V4.10，ADR-C68 实证）：
  改源码做验证的脚本必须 try/finally 恢复，且注入前校验锚点存在，
  找不到就显式报 INJECT-FAILED，绝不静默 continue。
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROG = os.path.join(ROOT, 'lib', 'services', 'progressive_diagnosis.dart')

BAK_DIR = os.path.join(tempfile.gettempdir(), 'adr_c69_mut')
BAK = {PROG: os.path.join(BAK_DIR, 'prog.bak')}

TEST = 'test/services/progressive_chunk_syndrome_coverage_test.dart'


def read(p):
    with io.open(p, encoding='utf-8', newline='') as f:
        return f.read()


def write(p, s):
    with io.open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(s)


def backup_all():
    if not os.path.isdir(BAK_DIR):
        os.makedirs(BAK_DIR)
    for dst, src in BAK.items():
        shutil.copyfile(dst, src)


def restore_all():
    for dst, src in BAK.items():
        write(dst, read(src))


def _flutter_cmd():
    for cand in ['flutter', 'flutter.bat']:
        p = shutil.which(cand)
        if p:
            return p
    for cand in [r'D:\flutter\bin\flutter.bat', r'D:\flutter\bin\flutter']:
        if os.path.exists(cand):
            return cand
    raise RuntimeError('找不到 flutter 可执行文件')


FLUTTER = _flutter_cmd()


def run_test():
    r = subprocess.run(
        [FLUTTER, 'test', TEST],
        cwd=ROOT, capture_output=True, text=True,
        encoding='utf-8', errors='replace', shell=False,
    )
    return r.returncode, (r.stdout or '') + (r.stderr or '')


def failing_tests(out):
    names = []
    in_block = False
    for line in out.splitlines():
        if line.startswith('Failing tests:'):
            in_block = True
            continue
        if not in_block:
            continue
        s = line.strip()
        if not s:
            break
        if s.startswith('Flutter assets') or s.startswith('... and '):
            continue
        if '.dart: ' not in s:
            continue
        names.append(s.split('.dart: ', 1)[-1])
    return names


# ── 变异定义 ──
LABELS_CALL = '  final labels = _activeSyndromeLabels();'
# A：最真实的「回退到 RN 逐字移植形态」——清单被写回多行字面量
RN_LIST_BLOCK = (
    '- P003 情绪标签化 / P004 信息倾泻症 / P005 视角漂移 / P006 节奏停滞\n'
    '- P007 句式节奏单一 / P008 语言堆砌 / P009 角色动机缺失 / P010 OC平面化\n'
    '- P011 对话疲劳症 / P012 张力不足症 / P013 开篇平庸症 / P014 结尾乏力症\n'
    '- P015 高潮疲软症 / P016 情节巧合过多症 / P017 伏笔失效症 / P018 人设崩塌症\n'
    '- P019 情感失真症 / P020 过渡生硬症 / P021 跳跃叙事/过度概括症'
)
RANGE_INTERP = '症候编号 ${_syndromeIdRange()}'
RANGE_HARD = '症候编号 P003-P027'
FALLBACK_NOTE = (
    '- 上面未列出的症候：例外情况以症候诊断手册为准；'
    '判定尺度与上述一致——只在读者体验确实会受损时才算症候'
)
CHUNK_CALL = "ChatMessage(role: 'system', content: kChunkSystemPrompt)"
LABELS_BODY = '      .map((s) => \'${s.id} ${s.name}\')'
LABELS_TRUNC = (
    "      .where((s) => s.id.compareTo('P022') < 0)\n"
    "      .map((s) => '${s.id} ${s.name}')"
)

MUTATIONS = [
    ('A', '清单回退为 RN 逐字多行字面量 → ①③⑤ 应失败', [
        (PROG, '${listBlock.join(\'\\n\')}', RN_LIST_BLOCK),
    ]),
    ('B', '范围改回硬编码 P003-P027 → ②③ 应失败', [
        (PROG, RANGE_INTERP, RANGE_HARD),
    ]),
    ('C', '删掉例外指引兜底句 → ④ 应失败', [
        # 兜底句后紧跟 ''';，无尾换行（首版多加 \n 导致锚点匹配失败）
        (PROG, FALLBACK_NOTE, ''),
    ]),
    ('D', 'analyzeChunk 换成别的 prompt → ⑤ 应失败', [
        (PROG, CHUNK_CALL, "ChatMessage(role: 'system', content: 'x')"),
    ]),
    ('F', '派生逻辑被截断到 P021 → ①② 应失败', [
        (PROG, LABELS_BODY, LABELS_TRUNC),
    ]),
]


def main():
    backup_all()
    results = []
    try:
        for tag, desc, edits in MUTATIONS:
            restore_all()
            ok_apply = True
            for path, old, new in edits:
                src = read(path)
                if old not in src:
                    print('[%s] 变异注入失败：找不到锚点片段 -> %r'
                          % (tag, old[:60]))
                    ok_apply = False
                    break
                write(path, src.replace(old, new, 1))
            if not ok_apply:
                results.append((tag, desc, 'INJECT-FAILED', []))
                continue

            code, out = run_test()
            names = failing_tests(out)
            if code == 0:
                verdict = '漏网 ✗'
            elif names:
                verdict = '拦截 ✓'
            else:
                verdict = '? 编译/解析异常'
            results.append((tag, desc, verdict, names))
            print('[%s] %s -> %s（失败 %d 项）' % (tag, desc, verdict, len(names)))
    finally:
        restore_all()

    print('\n===== 变异验证汇总 =====')
    for tag, desc, verdict, names in results:
        print('%s  %-44s %s' % (tag, desc, verdict))
        for n in names:
            print('        - %s' % n)
    leaked = [t for t, _, v, _ in results if v != '拦截 ✓']
    print('\n未拦截变异：%s' % (leaked if leaked else '无'))
    return 1 if leaked else 0


if __name__ == '__main__':
    sys.exit(main())
