// ─────────────────────────────────────────────────────────────
// reader_impact 示例「不得给具体数字」护栏（P0'-2）
//
// 病因：两处 reader_impact 示例句曾写死「不改这段，读者会在**前 200 字**内
//   走神，无法进入后续剧情」。模型把它当模板**逐字回声**（2026-09-30 取证
//   实测 43% 的条目以「不改这段，读者会」开头）——等于替作者**编造**了一个
//   它无从知道的具体影响范围（"前 200 字"这个量纲是示例自带的，不是从正文
//   推出来的）。
//
// 修法：删掉示例里的具体数字，并显式要求"不得照抄示例措辞"。
//
// 本护栏（按**出现位置**判，不用 contains —— 见 AGENTS.md V4.7 假判据教训）：
//   ① 注入侧（progressive_diagnosis.dart 的 buildMergePrompt）示例行无 `N 字`
//   ② 手册侧（syndrome_kb_content.dart，虽非注入区，同源缺陷一并守）
//   ③ 反向自检：护栏正则本身有效（对含「前 200 字」的样本必命中）
//
// 变异验证：把任一处示例改回「读者会在前 200 字内走神」→ ①② 必红。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/lib').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError('找不到包根目录（cwd=${Directory.current.path}）');
}

final Directory _root = _findPackageRoot();

/// 含 `reader_impact` 且含「示例」的行（即"给模型看的示例句"），全部取出。
List<String> _readerImpactExampleLines(String relPath) {
  final f = File('${_root.path}/$relPath');
  if (!f.existsSync()) {
    throw StateError('源文件不存在：$relPath（root=${_root.path}）');
  }
  return f
      .readAsStringSync()
      .split('\n')
      .where((l) => l.contains('reader_impact') && l.contains('示例'))
      .toList();
}

/// 示例句里的「具体数字 + 字」量纲（如 `前 200 字`）——被判为"编造影响范围"。
final RegExp _kConcreteMagnitude = RegExp(r'\d+\s*字');

void main() {
  group('P0\'-2 reader_impact 示例不含编造的具体量纲', () {
    for (final rel in const [
      'lib/services/progressive_diagnosis.dart',
      'lib/services/syndrome_kb_content.dart',
    ]) {
      test(rel, () {
        final lines = _readerImpactExampleLines(rel);
        expect(
          lines,
          isNotEmpty,
          reason: '$rel 里找不到 reader_impact 示例行（护栏判据失锚）',
        );
        for (final l in lines) {
          expect(
            _kConcreteMagnitude.hasMatch(l),
            isFalse,
            reason:
                '$rel 的 reader_impact 示例含具体量纲「${_kConcreteMagnitude.firstMatch(l)?.group(0)}」——'
                '模型会把它当模板逐字回声，等于编造影响范围（P0\'-2）。\n$l',
          );
        }
      });
    }

    test('护栏正则自身有效（变异回归）', () {
      expect(_kConcreteMagnitude.hasMatch('读者会在前 200 字内走神'), isTrue);
      expect(_kConcreteMagnitude.hasMatch('读者会在 3 字内出戏'), isTrue);
      expect(_kConcreteMagnitude.hasMatch('读者没有被说服的过程'), isFalse);
    });
  });
}
