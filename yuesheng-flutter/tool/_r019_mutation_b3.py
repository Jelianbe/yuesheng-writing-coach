# -*- coding: utf-8 -*-
"""R-019 批次三（getOrCreateSessionForChapter / callTeacherStream）判据级变异验证。"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

MUTATIONS = [
    ('lib/data/repositories/session_repository.dart',
     'test/data/repositories/session_repository_b23_test.dart', [
        ('M1 标题回退反转',
         "title: chapterTitle.trim().isEmpty ? '章节会话' : '诊断·$chapterTitle',",
         "title: chapterTitle.trim().isNotEmpty ? '章节会话' : '诊断·$chapterTitle',"),
        ('M2 章节查询反转',
         '      ..where((t) => t.chapterId.equals(chapterId))',
         '      ..where((t) => t.chapterId.notEquals(chapterId))'),
        # M3 用函数内定位（refType: 'chapter' 在两处出现，需锚定 _createChapterSession）
        ('M3 主引用反转',
         '__FUNC__#_createChapterSession#refType: \'chapter\',',
         '__FUNC__#_createChapterSession#refType: \'manuscript\','),
    ]),
    ('lib/services/teacher_service.dart',
     'test/services/teacher_service_test.dart', [
        ('M1 teacher 判定反转',
         '  if (parsed.teacher == null) {',
         '  if (parsed.teacher != null) {'),
        ('M2 一致性校验反转',
         '  if (!consistency.passed) {',
         '  if (consistency.passed) {'),
        ('M3 拦截状态失效',
         '    if (inTeacherBlock) return;',
         '    inTeacherBlock = true;'),
    ]),
]


def _flutter_cmd():
    for c in ['flutter', 'flutter.bat']:
        p = shutil.which(c)
        if p:
            return p
    raise RuntimeError('no flutter')


FLUTTER = _flutter_cmd()
total = 0
failed = []
for src_rel, test_rel, cases in MUTATIONS:
    src = ROOT / src_rel
    test = ROOT / test_rel
    orig = io.open(src, encoding='utf-8', newline='').read()
    eol = '\r\n' if orig.count('\r\n') >= orig.count('\n') / 2 else '\n'
    for name, anchor, mutated in cases:
        if anchor.startswith('__FUNC__#'):
            # 函数内定位：__FUNC__#<签名>#<锚点>，仅在函数体内唯一替换
            _, sig, inner = anchor.split('#')
            fn_idx = orig.index('  Future<String> ' + sig + '(')
            seg = orig[fn_idx:fn_idx + 2500]
            inner_e = inner.replace('\n', eol)
            if seg.count(inner_e) != 1:
                print('INJECT-FAILED: [{}] 函数内锚点 {} 处'.format(
                    name, seg.count(inner_e)))
                failed.append((name, '锚点缺失'))
                continue
            rel = seg.index(inner_e)
            a = inner_e
            m = mutated.split('#')[-1].replace('\n', eol)
            pos = fn_idx + rel
            total += 1
            try:
                patched = orig[:pos] + m + orig[pos + len(a):]
                io.open(src, 'w', encoding='utf-8', newline='').write(patched)
                r = subprocess.run([FLUTTER, 'test', str(test), '--no-pub'],
                                   cwd=str(ROOT), capture_output=True, text=True,
                                   timeout=300, encoding='utf-8', errors='replace', shell=False)
                out = r.stdout + r.stderr
                if 'All tests passed!' in out:
                    print('MUTATION-LOOSE: [{}] 漏网'.format(name))
                    failed.append((name, '漏网'))
                else:
                    print('MUTATION-KILL: [{}] 拦截 ✓'.format(name))
            finally:
                io.open(src, 'w', encoding='utf-8', newline='').write(orig)
            continue
        a, m = anchor.replace('\n', eol), mutated.replace('\n', eol)
        if a not in orig:
            print('INJECT-FAILED: [{}] 锚点未找到'.format(name))
            failed.append((name, '锚点缺失'))
            continue
        total += 1
        try:
            io.open(src, 'w', encoding='utf-8', newline='').write(orig.replace(a, m, 1))
            r = subprocess.run([FLUTTER, 'test', str(test), '--no-pub'],
                               cwd=str(ROOT), capture_output=True, text=True,
                               timeout=300, encoding='utf-8', errors='replace', shell=False)
            out = r.stdout + r.stderr
            if 'All tests passed!' in out:
                print('MUTATION-LOOSE: [{}] 漏网'.format(name))
                failed.append((name, '漏网'))
            else:
                print('MUTATION-KILL: [{}] 拦截 ✓'.format(name))
        finally:
            io.open(src, 'w', encoding='utf-8', newline='').write(orig)

print()
print('变异总数: {}, 未拦截: {}'.format(total, len(failed)))
for n, why in failed:
    print('  FAIL: {} — {}'.format(n, why))
sys.exit(1 if failed else 0)
