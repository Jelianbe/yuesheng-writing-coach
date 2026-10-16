// ─────────────────────────────────────────────────────────────
// W-19-B prompt 层护栏（2026-10-16 舰长批 R-027「除了18b都批」）
//
// 报批稿：docs/designs/2026-10-16-W19-B-prompt层R027报批稿.md
// 契约层已就绪（W-19-A commit cfbfd91f），本批补 prompt 侧三处注入：
//   ① _kMergeGuidanceBlock 追加 S3 三判据 + 铁律段（主生效位）
//   ② merge 输出格式段追加 intervention_value 字段说明行
//   ③ syndrome_kb_content.dart 手册尾副本按 **B 案** 只带范围说明一行
//
// 本护栏守四条不变量（都能变红）：
//   ① S3 三判据文案在生效侧且恰好 1 次（防复制漂移）
//   ② intervention_value 字段行在位，且晚于 S3 判据（先给判据再给字段契约）
//   ③ 正交性铁律在位（intervention_value ≠ severity 别名——防 LLM 学成马甲）
//   ④ 防御侧只带范围说明、不复制 S3 全文（A 案被报批稿否决：不注入的副本
//      复制 12 行 = 维护面 ×2 而收益 ≈0）
//
// 变异验证：
//   A 删 S3 块 → ① 失败
//   B 删字段行 → ② 失败
//   C 删铁律段 → ③ 失败
//   D 按 A 案把 S3 全文复制进防御侧 → ④ 失败
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

String _readSrc(String relPath) {
  final f = File('${_root.path}/$relPath');
  if (!f.existsSync()) {
    throw StateError('源文件不存在：$relPath（root=${_root.path}）');
  }
  return f.readAsStringSync();
}

int _count(String src, String needle) => needle.allMatches(src).length;

/// 生效侧：merge prompt 宿主（会被注入）
const String kEffectiveHost = 'lib/services/progressive_diagnosis.dart';

/// 防御侧：手册尾副本（按 ID 切片注入 ⇒ 从不注入，见
/// progressive_diagnosis.dart 对 _kMergeRelevanceGate 的注释）
const String kDefensiveHost = 'lib/services/syndrome_kb_content.dart';

/// S3 判据块头（报批稿 §二① 改后原文）
const String kS3Header = '干预价值（S3）三判据——对每条准备报出的症候依次自问';

/// S3 判据正文独有片段（B 案副本不应含——④ 的反向判据）
const String kS3BodyMarker = '可教：存在一个作者现在就能做的具体训练动作';

/// 正交性铁律（报批稿 §二① 铁律段）
const String kIronRule = 'intervention_value 与 severity 相互独立，不得互为别名或函数';

/// 字段说明行（报批稿 §二② 改后原文）
const String kFieldLine =
    '- intervention_value (high|medium|low): 按上述「干预价值（S3）三判据」评定的档位，缺省 low';

/// B 案范围说明（报批稿 §二③ B 案原文）
const String kBNote =
    '（干预价值 S3 三判据与 intervention_value 字段规范见 merge 指引块，本链路不输出该字段）';

void main() {
  group('① S3 三判据在生效侧且唯一', () {
    test(kEffectiveHost, () {
      final src = _readSrc(kEffectiveHost);
      expect(
        _count(src, kS3Header),
        1,
        reason:
            '$kEffectiveHost 中 S3 判据块头应恰好 1 次。\n'
            '（W-19-B：判据在 _kMergeGuidanceBlock 数量原则之后；若被删或复制成多份，'
            '先过舰长 R-027，不要偷改）',
      );
      expect(_count(src, kS3BodyMarker), 1, reason: 'S3 判据正文（可教条）应恰好 1 次');
    });
  });

  group('② 字段行在输出格式段且晚于 S3 判据', () {
    test('intervention_value 字段行在位', () {
      final src = _readSrc(kEffectiveHost);
      expect(
        _count(src, kFieldLine),
        1,
        reason: '输出格式段应恰好 1 条 intervention_value 字段说明行（W-19-B ②）',
      );
    });

    test('S3 判据先于字段行（先给判据再给字段契约）', () {
      final src = _readSrc(kEffectiveHost);
      final iS3 = src.indexOf(kS3Header);
      final iField = src.indexOf(kFieldLine);
      expect(iS3, isNot(-1), reason: '找不到 S3 判据');
      expect(iField, isNot(-1), reason: '找不到字段行');
      expect(
        iS3,
        lessThan(iField),
        reason:
            'S3 判据（_kMergeGuidanceBlock 内）必须先于输出格式段的字段行，'
            '否则「按上述三判据」无所指',
      );
    });
  });

  group('③ 正交性铁律在位', () {
    test(kEffectiveHost, () {
      final src = _readSrc(kEffectiveHost);
      expect(
        _count(src, kIronRule),
        1,
        reason:
            '正交性铁律应恰好 1 次。\n'
            '（W-19 设计稿 §2.3/§2.4：intervention_value 与 severity 独立，'
            '防 LLM 把干预价值学成严重度的马甲；删它须先过舰长 R-027）',
      );
    });
  });

  group('④ 防御侧按 B 案：只有范围说明，无 S3 全文', () {
    test(kDefensiveHost, () {
      final src = _readSrc(kDefensiveHost);
      expect(
        _count(src, kBNote),
        1,
        reason: '手册尾副本第 4 条数量原则末尾应恰好 1 条 B 案范围说明（W-19-B ③）',
      );
      expect(
        _count(src, kS3BodyMarker),
        0,
        reason:
            '防御侧不应复制 S3 判据全文——该副本从不注入（按 ID 切片）且不产 '
            'intervention_value 字段，复制 12 行 = 维护面 ×2 而收益 ≈0（A 案已被报批稿否决）。'
            '若分片链路将来要输出该字段，须回头补全文并重过 R-027',
      );
    });
  });

  group('⑤ 判据自身有效（变异回归）', () {
    test('S3 文本会被 ① 判绿、防御侧误同步会被 ④ 判红', () {
      final s3Sample =
          '$kS3Header，全「是」=high，两条「是」=medium，其余=low：\n$kS3BodyMarker';
      expect(_count(s3Sample, kS3Header), 1);
      expect(_count(s3Sample, kS3BodyMarker), 1);
      expect(_count(kBNote, kS3BodyMarker), 0);
      expect(_count('铁律：$kIronRule——L3 严重但本轮干预不动它应为 low', kIronRule), 1);
    });
  });
}
