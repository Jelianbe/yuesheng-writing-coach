// ADR-C118 理论提案 P1 批4（SUGGEST-001/008/020/021/022/023/025/026/028/035/062/079/080）落地护栏
// 守卫：新症候 P034（手册段+训练段）、P015 判据分型、T014/T029 技法段内追加、
//       新技法 T032、训练素材库（P018/P017/P007/P013）、P013 训练边界块、
//       P020 版式边界、P011/P019/P020 未发布读者反应边界（079/080）。
// 18 处断言 = 001×2（手册+训练）；008/020/021/022/023/025/026/028/035/062 各×1；
//             079 三段×3；080 三段×3。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

void main() {
  group('theory-proposal-p1-b4-landing', () {
    test('SUGGEST-001 -> P034 手册 就近可及候选', () {
      final c = getSyndromeContent(['P034']);
      expect(c, contains('就近可及候选'));
    });

    test('SUGGEST-001 -> P034 训练 有话题锚 vs 无话题锚', () {
      final c = getTrainingContent(['P034']);
      expect(c, contains('有话题锚 vs 无话题锚'));
    });

    test('SUGGEST-008 -> P015 真·崩塌', () {
      final c = getSyndromeContent(['P015']);
      expect(c, contains('真·崩塌'));
    });

    test('SUGGEST-020 -> T014 相对 keyness 分布', () {
      final c = getTechniqueContent(['T014']);
      expect(c, contains('相对 keyness 分布'));
    });

    test('SUGGEST-021 -> T029 桥接无效', () {
      final c = getTechniqueContent(['T029']);
      expect(c, contains('桥接无效'));
    });

    test('SUGGEST-022 -> T032 四者缺一环即动机链断裂', () {
      final c = getTechniqueContent(['T032']);
      expect(c, contains('四者缺一环即动机链断裂'));
    });

    test('SUGGEST-023 -> P018 训练 连接词与论元错配', () {
      final c = getTrainingContent(['P018']);
      expect(c, contains('连接词与论元错配'));
    });

    test('SUGGEST-025 -> P017 训练 合法插叙 vs 真离题', () {
      final c = getTrainingContent(['P017']);
      expect(c, contains('合法插叙 vs 真离题'));
    });

    test('SUGGEST-026 -> P007 训练 今昔方向变化', () {
      final c = getTrainingContent(['P007']);
      expect(c, contains('今昔方向变化'));
    });

    test('SUGGEST-028 -> P013 训练 是否留痕', () {
      final c = getTrainingContent(['P013']);
      expect(c, contains('是否留痕'));
    });

    test('SUGGEST-035 -> P020 不指挥字号', () {
      final c = getSyndromeContent(['P020']);
      expect(c, contains('不指挥字号'));
    });

    test('SUGGEST-062 -> P013 训练 检索入口，不是权威', () {
      final c = getTrainingContent(['P013']);
      expect(c, contains('检索入口，不是权威'));
    });

    test('SUGGEST-079 -> P011/P019/P020 评论情绪≠全文情绪', () {
      for (final id in ['P011', 'P019', 'P020']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('评论情绪≠全文情绪'));
      }
    });

    test('SUGGEST-080 -> P011/P019/P020 会喜欢/会扑', () {
      for (final id in ['P011', 'P019', 'P020']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('会喜欢/会扑'));
      }
    });
  });
}
