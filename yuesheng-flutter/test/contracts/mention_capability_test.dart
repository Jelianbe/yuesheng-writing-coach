// ─────────────────────────────────────────────────────────────
// 契约测试 — @提及解析能力
//
// 验证 MentionCapability 接口与实现（MentionParser）的满足关系。
// 依赖倒置：MentionParser implements MentionCapability；编译期子类型断言
// 由 dart analyze（门禁 1）保证，本测试补充注册表断言。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/mention_capability.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/services/mention_parser.dart';

// 编译期子类型断言：若 MentionParser 未正确 implements MentionCapability，
// 本文件无法通过 dart analyze（门禁 1）。
MentionCapability _mentionImplIsCapability(MentionParser parser) => parser;

void main() {
  group('MentionCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(MentionCapability),
      );
    });

    test('ParseResult / ParsedMention 字段存在且正确', () {
      const mention = ParsedMention(
        raw: '@我的小说',
        refType: 'manuscript',
        refId: 'm1',
        title: '我的小说',
        manuscriptId: 'm1',
      );
      expect(mention.raw, '@我的小说');
      expect(mention.refType, 'manuscript');
      expect(mention.refId, 'm1');
      expect(mention.title, '我的小说');

      const result = ParseResult(mentions: [], cleanedText: '文本');
      expect(result.mentions, isEmpty);
      expect(result.cleanedText, '文本');
    });

    test('MentionParser 编译期满足 MentionCapability', () {
      expect(_mentionImplIsCapability, isA<Function>());
    });
  });
}
