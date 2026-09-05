# -*- coding: utf-8 -*-
"""ADR-C74 K-9 护栏变异验证：逐 mutation 注入 diagnosis_flow_handler.dart
的 helper 判据 → 跑诊断链相关测试 → 恢复 → 记录是否被拦截。

判据级变异（V4.21 精神）：每个 mutation 反转/破坏一个 helper 的条件分支，
验证测试确实锚定了它。漏网 = 该分支是虚覆盖（V4.20），需补测试。

用法: python tool/_k9_mutation.py
硬要求（V4.10 / V4.18）：
  - try/finally 恢复 + 注入前锚点校验（INJECT-FAILED 显式报出）
  - 基线健康校验：无变异时测试必须全绿，否则直接 abort（防 V4.18 假绿）
  - 收尾人工 git diff 复核
"""
import io
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROG = os.path.join(ROOT, 'lib', 'services', 'diagnosis_flow_handler.dart')

BAK_DIR = os.path.join(tempfile.gettempdir(), 'adr_c74_k9_mut')
BAK = {PROG: os.path.join(BAK_DIR, 'dh.bak')}

# 诊断链相关测试（mutation 后跑这些，快速且直击 K-9 行为）
TESTS = [
    'test/services/chat_service_send_message_test.dart',
    'test/services/chat_service_phase_migration_test.dart',
    'test/services/diagnosis_lock_contract_test.dart',
]


def read(p):
    with io.open(p, encoding='utf-8', newline='') as f:
        return f.read()


def detect_eol(src):
    # V4.4 / V4.17：工作区文件多为 CRLF（autocrlf=true），锚点必须行尾自适应
    return '\r\n' if src.count('\r\n') >= src.count('\n') / 2 else '\n'


def adapt_eol(s, eol):
    # 锚点/替换文本均按 '\n' 书写，注入前替换为源文件主导行尾
    return s.replace('\n', eol) if eol != '\n' else s


def write(p, s):
    with io.open(p, 'w', encoding='utf-8', newline='') as f:
        f.write(s)


def backup_all():
    if not os.path.isdir(BAK_DIR):
        os.makedirs(BAK_DIR)
    shutil.copyfile(PROG, BAK[PROG])


def restore_all():
    write(PROG, read(BAK[PROG]))


def _flutter_cmd():
    for cand in ['flutter', 'flutter.bat']:
        p = shutil.which(cand)
        if p:
            return p
    raise RuntimeError('找不到 flutter 可执行文件')


FLUTTER = _flutter_cmd()


def run_tests():
    r = subprocess.run(
        [FLUTTER, 'test'] + TESTS,
        cwd=ROOT, capture_output=True, text=True,
        encoding='utf-8', errors='replace', shell=False,
    )
    return r.returncode, (r.stdout or '') + (r.stderr or '')


def all_passed(out):
    return 'All tests passed!' in out


def failed_names(out):
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


# ── 变异定义（判据级）──
MUTATIONS = [
    ('M1', 'Teacher 只诊断边界反转（!diagnosisOnly -> diagnosisOnly）→ 诊断链测试应失败', [
        (PROG,
         '    if (shouldTriggerTeacherForDiagnosis(diagnosis.syndromes) &&\n'
         '        !diagnosisOnly) {',
         '    if (shouldTriggerTeacherForDiagnosis(diagnosis.syndromes) &&\n'
         '        diagnosisOnly) {'),
    ]),
    ('M2', 'JSON 二次校验被跳过（if (diagnosis != null) -> == null）→ 测试应失败', [
        (PROG,
         '  }) {\n'
         '    if (diagnosis != null) {\n'
         '      final startIndex = fullContent.indexOf(kDiagnosisStart);',
         '  }) {\n'
         '    if (diagnosis == null) {\n'
         '      final startIndex = fullContent.indexOf(kDiagnosisStart);'),
    ]),
    ('M3', '空响应判真故障失效（if (combined...&&!treatAsValid) -> if (false)）→ onError 用例应失败', [
        (PROG,
         '    if (combinedContent.trim().isEmpty && !treatAsValid) {',
         '    if (false) {'),
    ]),
    ('M4', 'aborted 反转（if (resolved.aborted) -> !resolved.aborted）→ onError 用例应失败', [
        (PROG,
         '    if (resolved.aborted) {',
         '    if (!resolved.aborted) {'),
    ]),
    ('M5', '空诊断 + outline 兜底计数反转（c > 0 -> c < 0）→ 兜底用例应失败', [
        (PROG,
         '        if (c > 0) treatAsValid = true;',
         '        if (c < 0) treatAsValid = true;'),
    ], True),  # known：预存防御分支（空诊断+chapter ref+outline 实体），
    # 任何测试均未给 FlowHandler 装配 outlineRepo，故不可达。非 K-9 新增，
    # 触达需 reference/chapter/manuscript/outline 四层 fixture（R-010 不扩），
    # 登记在 ADR-C74 §10 收尾报告，不作为 K-9 门禁失败项。
]


def main():
    backup_all()
    # 基线健康校验（V4.18）：无变异时必须全绿，否则环境坏了别让坏结果冒充好结果
    code0, out0 = run_tests()
    if code0 != 0 or not all_passed(out0):
        print('BASELINE-UNHEALTHY: 无变异时测试非全绿（code=%d），abort' % code0)
        print(out0[-800:])
        restore_all()
        return 1
    print('基线健康：%s 全绿' % ', '.join(TESTS))

    results = []
    eol = detect_eol(read(PROG))
    try:
        for item in MUTATIONS:
            tag, desc, edits = item[0], item[1], item[2]
            known = len(item) > 3 and item[3]
            restore_all()
            ok_apply = True
            for path, old, new in edits:
                src = read(path)
                old = adapt_eol(old, eol)
                new = adapt_eol(new, eol)
                if old not in src:
                    print('[%s] 变异注入失败：找不到锚点片段 -> %r'
                          % (tag, old[:70]))
                    ok_apply = False
                    break
                write(path, src.replace(old, new, 1))
            if not ok_apply:
                results.append((tag, desc, 'INJECT-FAILED', [], known))
                continue

            code, out = run_tests()
            names = failed_names(out)
            if code == 0 and all_passed(out):
                verdict = '漏网 ✗'
            elif names:
                verdict = '拦截 ✓'
            else:
                verdict = '? 编译/解析异常'
            results.append((tag, desc, verdict, names, known))
            print('[%s] %s -> %s（失败 %d 项%s）'
                  % (tag, desc, verdict, len(names),
                     '，known 预存盲区' if known else ''))
    finally:
        restore_all()

    print('\n===== K-9 变异验证汇总 =====')
    for tag, desc, verdict, names, known in results:
        print('%s  %-46s %s%s' % (tag, desc, verdict,
                                  '（known 预存盲区）' if known else ''))
        for n in names:
            print('        - %s' % n)
    leaked = [t for t, _, v, _, k in results if v != '拦截 ✓' and not k]
    print('\n未拦截变异：%s' % (leaked if leaked else '无'))
    # 收尾复核：工作区必须与备份一致（V4.10）
    print('恢复后源码与备份一致：%s' % (read(PROG) == read(BAK[PROG])))
    return 1 if leaked else 0


if __name__ == '__main__':
    sys.exit(main())
