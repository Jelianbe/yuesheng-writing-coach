# -*- coding: utf-8 -*-
"""ADR-C68 护栏变异验证：逐个注入变异 → 跑测试 → 恢复 → 记录哪条断言失败。

用法: python tool/_c68_mutation.py
每次只注入一个变异，跑完立即从备份恢复，互不干扰。
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P1 = os.path.join(ROOT, 'lib', 'services', 'skills_diagnosis_p1.dart')
KB = os.path.join(ROOT, 'lib', 'services', 'syndrome_kb_content.dart')
# 备份放系统临时目录（用 tempfile 解析，避免 Git Bash /tmp 与 Windows 路径不一致）
BAK_DIR = os.path.join(tempfile.gettempdir(), 'adr_c68_mut')
BAK = {
    P1: os.path.join(BAK_DIR, 'p1.bak'),
    KB: os.path.join(BAK_DIR, 'kb.bak'),
}
TEST = 'test/services/diagnosis_output_semantics_test.dart'


def read(p):
    # newline=''：不做换行归一，避免写回时把 CRLF 整文件改成 LF
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


N35_BLOCK = (
    '> **体裁未确认 ≠ 不能诊断**（N35）：学员一上来就贴文本、还没说体裁时，诊断块按 §3.9\n'
    '> 照常附加，severity 先按**通用标准**标定（见 §一 容忍度矩阵——各体裁的"提高/降低"\n'
    '> 都是相对这个基准而言），同时在自然说明里顺带确认体裁。\n'
    '> 体裁确认后若该体裁阈值与通用标准不同，**从下一轮起按体裁调整**即可；不要为了\n'
    '> 等体裁而推迟本轮诊断，也不要因为体裁未定就降低置信度或省略诊断块。\n\n'
)

NAT_NOTE_OLD = '[用自然的语言向作者说明你识别到的主要问题，这是给作者看的对话内容]'
NAT_NOTE_NEW = (
    '[用自然的语言向作者说明本轮聚焦的 1-2 个主要问题'
    '（"聚焦"由教学层规则另定），这是给作者看的对话内容]'
)
JSON_NOTE = (
    '（**不受上面"聚焦 1-2 个"的限制**——两段管的是不同事：'
    '自然说明按教学层聚焦讲，syndromes 数组则按上文"不限制数量"全量识别）'
)

MUTATIONS = [
    ('A', '删掉 N35 裁决段落（① 应失败）', [
        (P1, N35_BLOCK, ''),
    ]),
    ('B', '把 N35 段落挪到 genre-guide 之外（① ② 应失败）', [
        (P1, N35_BLOCK, ''),
        (P1, 'const Skill _genreGuide = Skill(', N35_BLOCK + 'const Skill _genreGuide = Skill('),
    ]),
    ('C', '删掉③ JSON 段说明（⑤ 应失败，且不被②掩盖）', [
        (KB, JSON_NOTE + '\n', ''),
    ]),
    ('D', '把②挪到 index 内容最末端（脱离小节但仍在可注入范围，③ 应失败）', [
        (KB, NAT_NOTE_NEW, NAT_NOTE_OLD),
        (KB, 'final String kSyndromeManualContent =',
         NAT_NOTE_NEW + '\nfinal String kSyndromeManualContent ='),
    ]),
    ('H', '把②挪到「## 输出格式」之前（② 上边界 B 应失败）', [
        (KB, NAT_NOTE_NEW, NAT_NOTE_OLD),
        (KB, '## 输出格式',
         NAT_NOTE_NEW + '\n## 输出格式'),
    ]),
    ('E', '把③挪到「### JSON 数据部分」标题之前（③ 应失败）', [
        (KB, '### JSON 数据部分\n' + JSON_NOTE, JSON_NOTE + '\n### JSON 数据部分'),
    ]),
    ('F', '改掉「不限制问题数量」原文（④ 应失败）', [
        (KB, '不限制问题数量——识别到多少就报多少', '最多报告 3 个问题'),
    ]),
]


def _flutter_cmd():
    """定位 flutter 可执行文件（Windows 下需带 .bat，python 子进程无 shell PATH）。"""
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
        cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace',
        shell=False,
    )
    out = (r.stdout or '') + (r.stderr or '')
    return r.returncode, out


def failing_tests(out):
    """解析 flutter test 的 Failing tests 块，剔除噪声行。"""
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
        # 噪声：环境提示 / 截断提示 / 非测试路径行
        if s.startswith('Flutter assets') or s.startswith('... and '):
            continue
        if '.dart: ' not in s:
            continue
        names.append(s.split('.dart: ', 1)[-1])
    return names


def main():
    backup_all()
    results = []
    # try/finally 是硬要求：本批首轮就因脚本在 run_test() 抛异常而跳过恢复，
    # 把 N35 段落永久留在了「已变异」状态，后续四个变异的结果全被污染。
    try:
        for tag, desc, edits in MUTATIONS:
            restore_all()
            ok_apply = True
            for path, old, new in edits:
                src = read(path)
                if old not in src:
                    print('[%s] 变异注入失败：找不到锚点片段 -> %s' % (tag, old[:40]))
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
        print('%s  %-46s %s' % (tag, desc, verdict))
        for n in names:
            print('        - %s' % n)
    leaked = [t for t, _, v, _ in results if v != '拦截 ✓']
    print('\n未拦截变异：%s' % (leaked if leaked else '无'))
    return 1 if leaked else 0


if __name__ == '__main__':
    sys.exit(main())
