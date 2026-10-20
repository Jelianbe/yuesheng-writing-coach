// ─────────────────────────────────────────────────────────────
// W-19-B prompt 层护栏（2026-10-16 舰长批 R-027「除了18b都批」）
//
// 报批稿：docs/designs/2026-10-16-W19-B-prompt层R027报批稿.md
// 契约层已就绪（W-19-A commit cfbfd91f），本批补 prompt 侧三处注入：
//   ① _kMergeGuidanceBlock 追加 S3 三判据 + 铁律段（主生效位）
//   ② merge 输出格式段追加 intervention_value 字段说明行
//   ③ syndrome_kb_content.dart 手册尾副本按 **B 案** 只带范围说明一行
//
// ★ 2026-10-20 治理续批第二批（路 α · R-027 批准）修订本护栏（C7）：
//   S3 三判据被抽为**共享常量** `kInterventionValueS3Criteria`（落
//   lib/services/intervention_value.dart），两宿主（merge 链 / 单次链）各引用 1 次。
//   ⇒ 本护栏的口径随之变更：
//     ① 由「S3 文案在 merge 宿主恰好 1 次」改为
//        「S3 文案在**唯一定义源**恰好 1 次 + 两宿主各**引用**该常量 1 次」
//        （防复制漂移 + 防漏引用）；
//     ③ 正交性铁律同口径迁到唯一定义源；
//     ④ 防御侧口径反转：**单次链现在也输出 intervention_value**（路 α 的目的），
//        故「B 案范围说明」不再存在；改为断言「单次链已含 S3 段与 iv 字段行」，
//        且**手册尾副本**（按 ID 切片注入 ⇒ 从不注入的那份）仍无 S3 全文。
//   ★ 修订后不变量全部仍能变红（见文末变异验证）。
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

/// ★ 2026-10-20 新增：单次链宿主（`syndrome-diagnosis-index` 技能内容 =
///   `kSyndromeIndexContent` 的 footer）—— 路 α 后单次链**也输出** iv。
const String kSingleChainHost = 'lib/services/syndrome_kb_content.dart';

/// ★ 2026-10-20 新增：S3 三判据的**唯一定义源**（治理续批第二批 C6 抽取）。
const String kS3DefinitionHost = 'lib/services/intervention_value.dart';

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

/// ★ 2026-10-20：单次链 JSON 格式块里的 iv 字段行（治理续批第二批 C3）。
const String kSingleChainIvLine =
    '"intervention_value": "high | medium | low（按干预价值 S3 三判据评定，缺省 low）"';

/// ★ 2026-10-20：共享常量的引用名（两宿主各 1 次）。
/// ⚠️ 判据数的是**插值引用**（`$kInterventionValueS3Criteria`）而非**名字出现**——
///   名字还会出现在 import 行（`show kInterventionValueS3Criteria`）与注释里，
///   数名字会把「正确引用」误判成「引用 2 次」。插值 = 真正把它拼进 prompt。
const String kS3ConstName = 'kInterventionValueS3Criteria';

void main() {
  group('① S3 三判据唯一定义 + 两宿主各引用 1 次', () {
    test('唯一定义源中 S3 判据恰好 1 次（防复制漂移）', () {
      final src = _readSrc(kS3DefinitionHost);
      expect(
        _count(src, kS3Header),
        1,
        reason:
            '$kS3DefinitionHost 中 S3 判据块头应恰好 1 次。\n'
            '（治理续批第二批 C6：S3 三判据抽为共享常量，**唯一定义**；'
            '若被复制成多份，先过舰长 R-027，不要偷改）',
      );
      expect(_count(src, kS3BodyMarker), 1, reason: 'S3 判据正文（可教条）应恰好 1 次');
      expect(_count(src, kIronRule), 1, reason: '正交性铁律应在唯一定义源中恰好 1 次（③ 的新口径）');
    });

    test('merge 宿主恰好插值引用共享常量 1 次（且不复制 S3 全文）', () {
      final src = _readSrc(kEffectiveHost);
      expect(
        _count(src, r'$kInterventionValueS3Criteria'),
        1,
        reason:
            '$kEffectiveHost 应恰好引用 $kS3ConstName 一次。\n'
            '（引用次数 0 = 漏引用 ⇒ merge 链无 S3 判据；>1 = 重复引用/复制 ⇒ 漂移）',
      );
      expect(
        _count(src, kS3BodyMarker),
        0,
        reason:
            'merge 宿主**不得**内联 S3 判据全文——判据正文只在唯一定义源，'
            '宿主只插值引用（复制 12 行 = 维护面 ×2 且必然漂移）',
      );
    });

    test('单次链宿主恰好插值引用共享常量 1 次（且不复制 S3 全文）', () {
      final src = _readSrc(kSingleChainHost);
      expect(
        _count(src, r'$kInterventionValueS3Criteria'),
        1,
        reason:
            '$kSingleChainHost 应恰好引用 $kS3ConstName 一次'
            '（路 α：单次链自此输出 intervention_value）',
      );
      expect(
        _count(src, kS3BodyMarker),
        0,
        reason: '单次链宿主不得内联 S3 判据全文（唯一定义源纪律）',
      );
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
      // ★ 2026-10-20：判据正文已迁到唯一定义源 ⇒ 宿主内比较「常量引用位置」
      //   与「字段行位置」二者先后（宿主内仍是先插值判据、后声明字段契约）。
      final iS3 = src.indexOf(kS3ConstName);
      final iField = src.indexOf(kFieldLine);
      expect(iS3, isNot(-1), reason: '找不到 S3 常量引用');
      expect(iField, isNot(-1), reason: '找不到字段行');
      expect(
        iS3,
        lessThan(iField),
        reason:
            'S3 判据引用（_kMergeGuidanceBlock 内）必须先于输出格式段的字段行，'
            '否则「按上述三判据」无所指',
      );
    });

    test('★ 单次链 JSON 格式块含 iv 字段行（路 α · C3）', () {
      final src = _readSrc(kSingleChainHost);
      expect(
        _count(src, kSingleChainIvLine),
        1,
        reason: '单次链 JSON 格式块应恰好 1 条 intervention_value 字段行（治理续批第二批 C3）',
      );
    });
  });

  group('③ 正交性铁律在位（唯一定义源）', () {
    test('铁律只在唯一定义源出现一次', () {
      final def = _readSrc(kS3DefinitionHost);
      final merge = _readSrc(kEffectiveHost);
      final single = _readSrc(kSingleChainHost);
      expect(
        _count(def, kIronRule),
        1,
        reason:
            '正交性铁律应恰好 1 次。\n'
            '（W-19 设计稿 §2.3/§2.4：intervention_value 与 severity 独立，'
            '防 LLM 把干预价值学成严重度的马甲；删它须先过舰长 R-027）',
      );
      expect(
        _count(merge, kIronRule) + _count(single, kIronRule),
        0,
        reason: '两个宿主都不得复制铁律全文（唯一定义源纪律）',
      );
    });
  });

  group('④ 防御侧仍无 S3 全文（手册尾副本从不注入）', () {
    test('手册尾副本不含 S3 判据正文', () {
      // 手册尾副本 = kSyndromeManualContent 段落（按 ID 切片注入 ⇒ 从不注入）。
      final src = _readSrc(kDefensiveHost);
      final iManual = src.indexOf('kSyndromeManualContent');
      expect(iManual, isNot(-1), reason: '找不到 kSyndromeManualContent 段');
      final manual = src.substring(iManual);
      expect(
        _count(manual, kS3BodyMarker),
        0,
        reason:
            '手册尾副本不应复制 S3 判据全文——该副本从不注入（按 ID 切片）。'
            '若分片链路将来要输出该字段，须回头补全文并重过 R-027',
      );
    });

    test('★ 单次链已含 S3 段与形态段（B 案范围说明已退役）', () {
      final src = _readSrc(kSingleChainHost);
      expect(
        _count(src, '本链路不输出该字段'),
        0,
        reason:
            '路 α 后单次链自此输出 intervention_value，'
            '「本链路不输出该字段」的旧范围说明必须消失（残留 = 自相矛盾的 prompt）',
      );
      expect(
        _count(src, '## 干预价值（S3）三判据'),
        1,
        reason: '单次链应有 S3 段标题恰好 1 次（C2）',
      );
      expect(
        _count(src, '## 形态字段（仅量形式症候评定）'),
        1,
        reason: '单次链应有形态字段段标题恰好 1 次（C2）',
      );
    });
  });

  group('⑤ 判据自身有效（变异回归）', () {
    test('S3 文本会被 ① 判绿、宿主误内联会被 ① 判红', () {
      final s3Sample =
          '$kS3Header，全「是」=high，两条「是」=medium，其余=low：\n$kS3BodyMarker';
      expect(_count(s3Sample, kS3Header), 1);
      expect(_count(s3Sample, kS3BodyMarker), 1);
      expect(_count('铁律：$kIronRule——L3 严重但本轮干预不动它应为 low', kIronRule), 1);
    });
  });
}
