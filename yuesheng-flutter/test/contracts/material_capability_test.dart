// ─────────────────────────────────────────────────────────────
// 契约测试 — 素材能力
//
// 验证 MaterialCapability 接口可被现有实现满足。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/material_capability.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/services/chat_context_builder.dart' as ctx;

void main() {
  group('MaterialCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(MaterialCapability),
      );
    });

    test('parseParagraphAnchor 返回 ParagraphAnchor?', () {
      final anchor = ctx.parseParagraphAnchor(
        '{"chapterId":"ch1","startPara":1,"endPara":2}',
      );
      expect(anchor, isA<ctx.ParagraphAnchor?>());
      expect(anchor!.chapterId, 'ch1');
      expect(anchor.startPara, 1);
      expect(anchor.endPara, 2);
    });

    test('parseParagraphAnchor null 输入返回 null', () {
      final anchor = ctx.parseParagraphAnchor(null);
      expect(anchor, isNull);
    });

    test('extractParagraphWindow 返回 String', () {
      final content = '第一段。\n第二段。\n第三段。';
      // 0-based: startPara=0 → 第一段, endPara=1 → 第二段
      final window = ctx.extractParagraphWindow(content, 0, 1);
      expect(window, isA<String>());
      expect(window, contains('第一段'));
    });

    test('formatAttachedFilesContext 返回 nullable String', () {
      final result = ctx.formatAttachedFilesContext([]);
      expect(result, isA<String?>());
    });

    test('接口可被实现（implements 编译验证）', () {
      final impl = _MaterialContractAdapter();
      expect(impl, isA<MaterialCapability>());
    });
  });
}

class _MaterialContractAdapter implements MaterialCapability {
  @override
  String? formatAttachedFiles(List<ctx.AttachedFileInfo> files) =>
      ctx.formatAttachedFilesContext(files);

  @override
  ctx.ParagraphAnchor? parseParagraphAnchor(String? excerptRangeJson) =>
      ctx.parseParagraphAnchor(excerptRangeJson);

  @override
  String extractParagraphWindow(
    String content,
    int startPara,
    int endPara,
  ) =>
      ctx.extractParagraphWindow(content, startPara, endPara);
}
