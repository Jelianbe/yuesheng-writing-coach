// ─────────────────────────────────────────────────────────────
// 契约测试 — 素材能力
//
// 验证 MaterialCapability 接口可被现有实现 MaterialCapabilityImpl 满足
//（编译期 implements 断言 + 实例方法行为校验，天然规避同名方法自递归）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/material_capability.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/services/chat_context_builder.dart';

void main() {
  group('MaterialCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(MaterialCapability),
      );
    });

    test('MaterialCapabilityImpl 满足契约（编译期 implements 断言 + 行为）', () {
      final impl = MaterialCapabilityImpl();
      expect(impl, isA<MaterialCapability>());

      // parseParagraphAnchor：经契约实例方法消费，不自递归
      expect(impl.parseParagraphAnchor(null), isNull);
      final anchor = impl.parseParagraphAnchor(
        '{"chapterId":"ch1","startPara":1,"endPara":2}',
      );
      expect(anchor, isNotNull);
      expect(anchor!.chapterId, 'ch1');
      expect(anchor.startPara, 1);
      expect(anchor.endPara, 2);

      // extractParagraphWindow：0-based 闭区间
      final window = impl.extractParagraphWindow(
        '第一段。\n第二段。\n第三段。',
        0,
        1,
      );
      expect(window, contains('第一段'));
      expect(window, contains('第二段'));

      // formatAttachedFiles：空列表 → null
      expect(impl.formatAttachedFiles([]), isNull);
    });

    test('顶层纯函数行为（向后兼容）', () {
      final anchor = parseParagraphAnchor(
        '{"chapterId":"ch1","startPara":1,"endPara":2}',
      );
      expect(anchor, isA<ParagraphAnchor?>());
      expect(anchor!.chapterId, 'ch1');
      expect(extractParagraphWindow('a\nb\nc', 0, 1), contains('a'));
    });
  });
}
