// ─────────────────────────────────────────────────────────────
// 契约测试 — GenUI 组件能力
//
// 验证 GenUiCapability 接口可被现有实现满足。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/contracts/genui_capability.dart';
import 'package:writingcoach/contracts/capability_registry.dart';
import 'package:writingcoach/services/genui_parser.dart';
import 'package:writingcoach/services/genui_validator.dart';

void main() {
  group('GenUiCapability 契约', () {
    test('接口在注册表中注册', () {
      expect(
        CapabilityContractRegistry.contractTypes,
        contains(GenUiCapability),
      );
    });

    test('componentWhitelist 包含 5 种类型', () {
      expect(kGenuiWhitelist.length, 5);
      expect(kGenuiWhitelist, containsAll(['diff', 'quiz', 'stat', 'progress', 'timeline']));
    });

    test('parseGenuiBlock 无块时返回 null', () {
      final result = parseGenuiBlock('普通文本无 GenUI 块');
      expect(result, isNull);
    });

    test('parseGenuiBlock 有合法块返回组件列表', () {
      const text = '[YS_GENUI]{"type":"diff","title":"对比","before":"旧","after":"新"}[/YS_GENUI]';
      final result = parseGenuiBlock(text);
      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result.first.type, 'diff');
    });

    test('validateGenuiComponent 返回 nullable GenUiComponent', () {
      final valid = validateGenuiComponent({
        'type': 'diff',
        'before': '旧',
        'after': '新',
      });
      expect(valid, isA<GenUiComponent?>());
      expect(valid, isNotNull);

      final invalid = validateGenuiComponent({'type': 'unknown_type'});
      expect(invalid, isNull);
    });

    test('接口可被实现（implements 编译验证）', () {
      final impl = _GenUiContractAdapter();
      expect(impl, isA<GenUiCapability>());
    });
  });
}

class _GenUiContractAdapter implements GenUiCapability {
  @override
  Set<String> get componentWhitelist => kGenuiWhitelist;

  @override
  List<GenUiComponent>? parseGenuiBlock(String rawText) =>
      parseGenuiBlockRaw(rawText);

  @override
  GenUiComponent? validateGenuiComponent(Map<String, dynamic> raw) =>
      validateGenuiComponentRaw(raw);
}

List<GenUiComponent>? parseGenuiBlockRaw(String rawText) =>
    parseGenuiBlock(rawText);

GenUiComponent? validateGenuiComponentRaw(Map<String, dynamic> raw) =>
    validateGenuiComponent(raw);
