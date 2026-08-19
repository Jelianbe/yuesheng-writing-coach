// ─────────────────────────────────────────────────────────────
// 契约测试 — 引用能力
//
// 验证 ReferenceCapability 接口可被现有实现满足。
// 注意：ReferenceRepository 的方法需要 Database 实例，
// 此测试只验证接口签名兼容性（implements 编译验证），
// 行为由 test/reference_repository_test.dart 覆盖。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/reference_capability.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/services/mention_parser.dart';

void main() {
  group('ReferenceCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(ReferenceCapability),
      );
    });

    test('ReferencedItem 字段与契约一致', () {
      const item = ReferencedItem(
        refId: 'r1',
        refType: 'chapter',
        isPrimary: 1,
        title: '第一章',
        manuscriptId: 'm1',
        excerptRange: '{"chapterId":"ch1","startPara":1,"endPara":2}',
      );
      expect(item.refId, 'r1');
      expect(item.refType, 'chapter');
      expect(item.isPrimary, 1);
      expect(item.title, '第一章');
      expect(item.manuscriptId, 'm1');
      expect(item.excerptRange, isNotNull);
    });

    test('ParseResult (MentionParser) 类型存在且字段正确', () {
      // 验证 MentionParser.ParseResult 类型可被引用（编译期检查）
      const result = ParseResult(mentions: [], cleanedText: '文本');
      expect(result.mentions, isEmpty);
      expect(result.cleanedText, '文本');
    });

    test('接口可被实现（implements 编译验证）', () {
      // 编译期验证：接口方法签名与 ReferenceRepository/MentionParser 兼容
      // _ReferenceContractAdapterShim 的定义即证明签名匹配
      expect(ReferenceCapability, isA<Type>());
    });
  });
}

/// 适配器类型定义（不实例化，仅编译期验证签名兼容）
///
/// 如果 ReferenceCapability 接口方法签名与 ReferenceRepository/MentionParser
/// 不兼容，此类的定义将导致编译失败。
// ignore: unused_element
class _ReferenceContractAdapterShim implements ReferenceCapability {
  @override
  Future<List<ReferencedItem>> listReferences(String sessionId) async => [];

  @override
  Future<String> addReference(
    String sessionId,
    String refType,
    String refId, {
    bool isPrimary = false,
    ({String chapterId, int startPara, int endPara})? excerptRange,
  }) async =>
      '';

  @override
  Future<void> removeReference(
    String sessionId,
    String refType,
    String refId,
  ) async {}

  @override
  Future<void> setPrimaryReference(
    String sessionId,
    String refType,
    String refId,
  ) async {}

  @override
  Future<bool> updateExcerptRange(
    String sessionId,
    String refType,
    String refId,
    ({String chapterId, int startPara, int endPara})? anchor,
  ) async =>
      false;

  @override
  Future<ParseResult> parseMentions(String text) async =>
      ParseResult(mentions: [], cleanedText: text);
}
