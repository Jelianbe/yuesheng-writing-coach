// ─────────────────────────────────────────────────────────────
// FT-23 显式压缩协议：单元测试
//
// 覆盖路径：
//   CompressionLevel.fromString:
//     #1 concise/standard/detailed 正确解析
//     #2 未知值降级为 standard
//     #3 null 降级为 standard
//   getCompressionRule:
//     #4 concise：保留三要素 + 裁剪铺垫/重复/理论 + 铺垫 0 行
//     #5 standard：保留三要素 + 不裁剪 + 铺垫 ≤2 行
//     #6 detailed：保留三要素 + 不裁剪 + 不限制铺垫
//     #7 三档都保留三要素（核心不变）
//   buildCompressionDirective:
//     #8 concise 指令含保留要素 + 裁剪要素 + 铺垫 0 行
//     #9 detailed 指令含"全量输出"
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/compression_protocol.dart';

void main() {
  group('FT-23 CompressionLevel.fromString', () {
    test('#1 concise/standard/detailed 正确解析', () {
      expect(CompressionLevel.fromString('concise'), CompressionLevel.concise);
      expect(
        CompressionLevel.fromString('standard'),
        CompressionLevel.standard,
      );
      expect(
        CompressionLevel.fromString('detailed'),
        CompressionLevel.detailed,
      );
    });

    test('#2 未知值降级为 standard', () {
      expect(CompressionLevel.fromString('unknown'), CompressionLevel.standard);
      expect(CompressionLevel.fromString(''), CompressionLevel.standard);
      expect(CompressionLevel.fromString('CONCISE'), CompressionLevel.standard);
    });

    test('#3 null 降级为 standard', () {
      expect(CompressionLevel.fromString(null), CompressionLevel.standard);
    });
  });

  group('FT-23 getCompressionRule', () {
    test('#4 concise：保留三要素 + 裁剪铺垫/重复/理论 + 铺垫 0 行', () {
      final rule = getCompressionRule(CompressionLevel.concise);
      expect(rule.retainElements, containsAll(['问题点', '改善方向', '证据']));
      expect(rule.droppableElements, isNotEmpty);
      expect(rule.droppableElements, containsAll(['铺垫/寒暄', '重复解释', '详细理论背景']));
      expect(rule.maxPreambleLines, 0);
    });

    test('#5 standard：保留三要素 + 不裁剪 + 铺垫 ≤2 行', () {
      final rule = getCompressionRule(CompressionLevel.standard);
      expect(rule.retainElements, containsAll(['问题点', '改善方向', '证据']));
      expect(rule.droppableElements, isEmpty);
      expect(rule.maxPreambleLines, 2);
    });

    test('#6 detailed：保留三要素 + 不裁剪 + 不限制铺垫', () {
      final rule = getCompressionRule(CompressionLevel.detailed);
      expect(rule.retainElements, containsAll(['问题点', '改善方向', '证据']));
      expect(rule.droppableElements, isEmpty);
      expect(rule.maxPreambleLines, isNull);
    });

    test('#7 三档都保留三要素（核心不变）', () {
      for (final level in CompressionLevel.values) {
        final rule = getCompressionRule(level);
        expect(
          rule.retainElements,
          containsAll(['问题点', '改善方向', '证据']),
          reason: '$level 应保留三要素',
        );
      }
    });
  });

  group('FT-23 buildCompressionDirective', () {
    test('#8 concise 指令含保留要素 + 裁剪要素 + 铺垫 0 行', () {
      final directive = buildCompressionDirective(CompressionLevel.concise);
      expect(directive, contains('concise'));
      expect(directive, contains('必须保留'));
      expect(directive, contains('问题点'));
      expect(directive, contains('改善方向'));
      expect(directive, contains('证据'));
      expect(directive, contains('可以裁剪'));
      expect(directive, contains('铺垫/寒暄'));
      expect(directive, contains('铺垫/寒暄允许行数：≤0'));
      expect(directive, contains('零铺垫'));
    });

    test('#9 detailed 指令含"全量输出"', () {
      final directive = buildCompressionDirective(CompressionLevel.detailed);
      expect(directive, contains('detailed'));
      expect(directive, contains('全量输出'));
      expect(directive, contains('不裁剪'));
      // detailed 不应有"可以裁剪"
      expect(directive, isNot(contains('可以裁剪')));
    });

    test('#10 standard 指令含保留要素 + 铺垫 ≤2 行', () {
      final directive = buildCompressionDirective(CompressionLevel.standard);
      expect(directive, contains('standard'));
      expect(directive, contains('必须保留'));
      expect(directive, contains('问题点'));
      expect(directive, contains('铺垫/寒暄允许行数：≤2'));
      // standard 不应有"可以裁剪"
      expect(directive, isNot(contains('可以裁剪')));
    });
  });
}
