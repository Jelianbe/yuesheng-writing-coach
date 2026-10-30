// ─────────────────────────────────────────────────────────────
// T-20261024-05 批 2 · excluded 字段全链 —— 判据 1「模板可产出」
//
// 落点（报批稿 ①1 / ①2，本单规格真源）：
//   - lib/services/chat_service.dart · kDiagnosisProtocolSuffix（user 侧后缀）
//   - lib/services/syndrome_kb_content.dart · index 模板（system 侧协议块）
//
// 断言面（grep 源码文本，不依赖运行期装配）：
//   ① 两处模板都含报批稿逐字 excluded 行；
//   ② 该行行位约束：在 "syndromes" 之后、"suggested_actions" 之前（与 syndromes 同级）；
//   ③ 行内 JSON 片段格式合法（可 jsonDecode、恰好两键）；
//   ④ index 面：批 B 伪问题段修订句已替换旧矛盾句的授权落点（新句关键片段）。
//
// 防假绿纪律（flutter-widget-test-false-green ①）：
//   每条「存在」断言之前先有阳性对照（同一块模板的既有键仍在），
//   避免「整块模板被删空后子串空过」。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 报批稿逐字 excluded 行（两份模板同一行，缩进随文件）。
/// 截取行内 JSON 对象片段做格式断言（不含外层引号与行尾逗号）。
const String kExcludedRowJson = '{"syndrome_id": "P017", "reason": "排除理由（可选）"}';

/// 批 B 新句关键片段（报批稿 ①2(b)，2026-10-30 舰长「批 B」逐字）。
const String kPseudoIssueNewFragment = 'JSON 中的排除项见 excluded 字段';

String _readSource(String relativePath) =>
    File(relativePath).readAsStringSync();

void main() {
  group('判据 1 · 模板可产出（grep 源码断言）', () {
    const suffixPath = 'lib/services/chat_service.dart';
    const indexPath = 'lib/services/syndrome_kb_content.dart';

    test('① suffix（chat_service.dart）：excluded 行存在且位序合法', () {
      final src = _readSource(suffixPath);

      // 阳性对照：本批动的就是 kDiagnosisProtocolSuffix 这块模板。
      expect(
        src,
        contains('kDiagnosisProtocolSuffix'),
        reason: '常量块应仍在（防整块模板被误删后子串空过）',
      );

      // 判据：excluded 逐字行存在。
      expect(
        src,
        contains(kExcludedRowJson),
        reason: 'kDiagnosisProtocolSuffix 必须按报批稿 ①1 逐字插入 excluded 行',
      );

      // 位序约束：与 syndromes 同级、在 suggested_actions 之前。
      final atExcluded = src.indexOf(kExcludedRowJson);
      final atSyndromes = src.indexOf('"syndromes"');
      final atSuggested = src.indexOf('"suggested_actions"');
      expect(
        atSyndromes,
        lessThan(atExcluded),
        reason: 'excluded 行必须在 "syndromes" 数组闭合之后（与之同级）',
      );
      expect(
        atExcluded,
        lessThan(atSuggested),
        reason: 'excluded 行必须在 "suggested_actions" 之前',
      );

      // 格式合法：行内 JSON 片段可解码、恰好两键。
      final decoded = jsonDecode(kExcludedRowJson) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {'syndrome_id', 'reason'});
      expect(decoded['syndrome_id'], 'P017');
    });

    test('② index（syndrome_kb_content.dart）：excluded 行存在且位序合法', () {
      final src = _readSource(indexPath);

      // 阳性对照：index 模板块（协议 JSON 示例）应仍在。
      expect(
        src,
        contains('"suggested_actions"'),
        reason: 'index 协议块应仍在（防整块模板被误删后子串空过）',
      );

      // 判据：excluded 逐字行存在。
      expect(
        src,
        contains(kExcludedRowJson),
        reason: 'index 模板必须按报批稿 ①2(a) 逐字插入 excluded 行',
      );

      // 位序约束：与 syndromes 同级、在 suggested_actions 之前。
      final atExcluded = src.indexOf(kExcludedRowJson);
      final atSyndromes = src.indexOf('"syndromes"');
      final atSuggested = src.indexOf('"suggested_actions"');
      expect(
        atSyndromes,
        lessThan(atExcluded),
        reason: 'index 面 excluded 行必须在 "syndromes" 数组闭合之后',
      );
      expect(
        atExcluded,
        lessThan(atSuggested),
        reason: 'index 面 excluded 行必须在 "suggested_actions" 之前',
      );
    });

    test('③ index 面：批 B 伪问题段修订句已落到授权落点', () {
      final src = _readSource(indexPath);

      // 阳性对照：index 模板结构标记仍在（防模板被误删后片段断言空过；
      // 不用带弯引号的段标题做对照——引号字符在双处出现、易误匹配注释行）。
      expect(
        src,
        contains('[YS_DIAGNOSIS]'),
        reason: 'index 协议块应仍在（防整块模板被误删后子串空过）',
      );

      // 判据：新句关键片段存在（报批稿 ①2(b) 批 B 逐字）。
      expect(
        src,
        contains(kPseudoIssueNewFragment),
        reason:
            '伪问题段末句必须按批 B 修订为「$kPseudoIssueNewFragment」——'
            '旧句「JSON 中不需要包含排除项」与新字段互相矛盾',
      );
    });
  });
}
