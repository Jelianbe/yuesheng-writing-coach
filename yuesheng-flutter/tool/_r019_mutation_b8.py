# -*- coding: utf-8 -*-
"""R-019 批次八（applyOutlineEntitiesFromContent / parseDiagnosis）判据级变异验证。"""
import io
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

MUTATIONS = [
    ('lib/services/diagnosis_committer.dart',
     'test/services/diagnosis_committer_outline_test.dart', [
        ('M1 非 chapter 引用放行',
         "    if (pRef?.refType != 'chapter') return;",
         "    if (pRef?.refType == 'chapter') return;"),
        ('M2 空 entities 不跳过',
         '    if (outlineExtraction == null || outlineExtraction.entities.isEmpty) {\n'
         '      return;\n'
         '    }',
         '    if (outlineExtraction == null) {\n'
         '      return;\n'
         '    }'),
        ('M3 空引用列表不返回 null',
         '      final refs = await _referenceRepo.listReferences(sessionId);\n'
         '      if (refs.isEmpty) return null;',
         '      final refs = await _referenceRepo.listReferences(sessionId);'),
    ]),
    ('lib/services/diagnosis_parser.dart',
     'test/services/diagnosis_parser_test.dart', [
        ('M1 prefix 不剥 FACT',
         '  final prefix = stripFactBlock(\n'
         '    stripOutlineBlock(rawText.substring(0, startIndex)),\n'
         '  ).trimRight();',
         '  final prefix = stripOutlineBlock(rawText.substring(0, startIndex))\n'
         '      .trimRight();'),
        ('M2 无结束标记不降级',
         "  if (endIndex == -1) {\n"
         "    // ADR-C63：此前静默丢弃（无日志）。模型以为有反馈回路，实际没有\n"
         "    // → 会一直填下去，每一轮都静默失败（N26「永久卡死而非抖动一次」）。\n"
         "    return ParseResult(\n"
         "      displayContent: displayContent,\n"
         "      diagnosis: null,\n"
         "      rejectReason: 'marker_end_missing',\n"
         "    );\n"
         "  }",
         "  if (endIndex == -1) {\n"
         "    return ParseResult(\n"
         "      displayContent: displayContent,\n"
         "      diagnosis: null,\n"
         "    );\n"
         "  }"),
        ('M3 suffix 不剥协议块',
         '  final suffix = endIndex == -1\n'
         '      ? \'\'\n'
         '      : stripFactBlock(\n'
         '          stripOutlineBlock(rawText.substring(endIndex + kDiagnosisEnd.length)),\n'
         '        ).trimLeft();',
         '  final suffix = endIndex == -1\n'
         '      ? \'\'\n'
         '      : stripOutlineBlock(rawText.substring(endIndex + kDiagnosisEnd.length))\n'
         '          .trimLeft();'),
    ]),
]


def _flutter():
    for c in ['flutter', 'flutter.bat']:
        p = shutil.which(c)
        if p:
            return p
    raise RuntimeError('no flutter')


FLUTTER = _flutter()
total = 0
failed = []
for src_rel, test_rel, cases in MUTATIONS:
    src = ROOT / src_rel
    test = ROOT / test_rel
    orig = io.open(src, encoding='utf-8', newline='').read()
    eol = '\r\n' if orig.count('\r\n') >= orig.count('\n') / 2 else '\n'
    for name, anchor, mutated in cases:
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
