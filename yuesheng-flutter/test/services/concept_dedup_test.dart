// ─────────────────────────────────────────────────────────────
// FT-21 多轮概念去重：单元测试
//
// 覆盖路径：
//   ConceptRegistry:
//     #1 空注册表 → isRecentlyExplained 返回 false
//     #2 注册概念 → isRecentlyExplained 返回 true
//     #3 过期清理 → 超 5 轮的概念被移除
//   detectDuplicateConcepts:
//     #4 空入参 → 全部为新概念
//     #5 全部已重复 → 全部为 duplicate
//     #6 混合（新+重复）→ 正确分类
//     #7 窗口边界（第 4 轮重复 / 第 5 轮过期）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/concept_dedup.dart';

void main() {
  group('FT-21 ConceptRegistry', () {
    test('#1 空注册表 → isRecentlyExplained 返回 false', () {
      final registry = ConceptRegistry();
      expect(registry.isEmpty, isTrue);
      expect(registry.isRecentlyExplained('过渡句', 1), isFalse);
    });

    test('#2 注册概念 → isRecentlyExplained 返回 true', () {
      final registry = ConceptRegistry();
      registry.register('过渡句', 1);
      expect(registry.length, 1);
      expect(registry.isRecentlyExplained('过渡句', 2), isTrue);
      expect(registry.isRecentlyExplained('情绪标签化', 2), isFalse);
    });

    test('#3 过期清理 → 超 5 轮的概念被移除', () {
      final registry = ConceptRegistry();
      registry.register('过渡句', 1);
      registry.register('伏笔', 3);
      expect(registry.length, 2);

      // turn=6: 过渡句（turn=1, 差5轮）过期；伏笔（turn=3, 差3轮）未过期
      registry.pruneExpired(6);
      expect(registry.length, 1);
      expect(registry.isRecentlyExplained('过渡句', 6), isFalse);
      expect(registry.isRecentlyExplained('伏笔', 6), isTrue);
    });
  });

  group('FT-21 detectDuplicateConcepts', () {
    test('#4 空入参 → 全部为新概念', () {
      final registry = ConceptRegistry();
      final result = detectDuplicateConcepts(
        incomingConcepts: ['过渡句', '情绪标签化'],
        registry: registry,
        currentTurn: 1,
      );
      expect(result.newConcepts.length, 2);
      expect(result.duplicateConcepts, isEmpty);
      expect(result.hasDuplicates, isFalse);
    });

    test('#5 全部已重复 → 全部为 duplicate', () {
      final registry = ConceptRegistry()
        ..register('过渡句', 1)
        ..register('情绪标签化', 1);
      final result = detectDuplicateConcepts(
        incomingConcepts: ['过渡句', '情绪标签化'],
        registry: registry,
        currentTurn: 2,
      );
      expect(result.newConcepts, isEmpty);
      expect(result.duplicateConcepts.length, 2);
      expect(result.hasDuplicates, isTrue);
    });

    test('#6 混合（新+重复）→ 正确分类', () {
      final registry = ConceptRegistry()..register('过渡句', 1);
      final result = detectDuplicateConcepts(
        incomingConcepts: ['过渡句', '伏笔', '爽点'],
        registry: registry,
        currentTurn: 2,
      );
      expect(result.newConcepts.length, 2);
      expect(result.newConcepts, containsAll(['伏笔', '爽点']));
      expect(result.duplicateConcepts, equals(['过渡句']));
      expect(result.hasDuplicates, isTrue);
    });

    test('#7 窗口边界（第 4 轮重复 / 第 5 轮过期）', () {
      final registry = ConceptRegistry()..register('过渡句', 1);

      // turn=5: 差 4 轮 < 5 → 仍重复
      final result1 = detectDuplicateConcepts(
        incomingConcepts: ['过渡句'],
        registry: registry,
        currentTurn: 5,
      );
      expect(result1.duplicateConcepts, equals(['过渡句']));
      expect(result1.newConcepts, isEmpty);

      // turn=6: 差 5 轮 >= 5 → 过期，不再是重复
      final result2 = detectDuplicateConcepts(
        incomingConcepts: ['过渡句'],
        registry: registry,
        currentTurn: 6,
      );
      expect(result2.duplicateConcepts, isEmpty);
      expect(result2.newConcepts, equals(['过渡句']));
    });
  });
}
