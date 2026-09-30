// ─────────────────────────────────────────────────────────────
// L3 症候/技法知识库检索测试
// 2026-08-08 批次 22 步骤②：syndrome-diagnosis.ts / technique-library.ts 搬运 + 接线
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('syndrome 知识库', () {
    test('索引内容完整（含 P001-P023 映射表）', () {
      expect(kSyndromeIndexContent, startsWith('# SKILL: 写作问题→症候 ID 映射表'));
      for (final id in kSyndromeIds) {
        expect(kSyndromeIndexContent, contains('| $id |'), reason: '索引缺 $id');
      }
    });

    test('手册内容完整（含 P001/P017/P018 定义）', () {
      expect(kSyndromeManualContent, startsWith('# SKILL: 症候诊断手册'));
      expect(kSyndromeManualContent, contains('### P001 情绪标签化'));
      expect(kSyndromeManualContent, contains('### P017 跳跃叙事/过度概括症'));
      expect(kSyndromeManualContent, contains('### P018 重复用词/基础语病'));
    });

    test('手册含批次15 网文商业症候完整定义', () {
      for (final name in [
        'P013 高潮疲软症',
        'P019 章节钩子缺失症',
        'P020 追读动力不足症',
        'P011 开篇平庸症',
      ]) {
        expect(
          kSyndromeManualContent,
          contains('### $name'),
          reason: '手册缺 $name',
        );
      }
      final content = getSyndromeContent(['P013']);
      expect(content, contains('### P013 高潮疲软症'));
      expect(content, contains('核心问题'));
      expect(content, contains('判断原则'));
      expect(content, contains('推荐教学动作'));
    });

    test('手册含批次23 新症候 P021 完整定义', () {
      expect(kSyndromeManualContent, contains('### P021 画面感缺失症'));
      final content = getSyndromeContent(['P021']);
      expect(content, contains('### P021 画面感缺失症'));
      expect(content, contains('核心问题'));
      expect(content, contains('判断原则'));
      expect(content, contains('推荐教学动作'));
      expect(content, contains('首选 A006 感官全开'));
    });

    test('手册含 P005 句式节奏单一 完整定义', () {
      expect(kSyndromeManualContent, contains('### P005 句式节奏单一'));
      final content = getSyndromeContent(['P005']);
      expect(content, contains('### P005 句式节奏单一'));
      expect(content, contains('核心问题'));
      expect(content, contains('判断原则'));
      expect(content, contains('推荐教学动作'));
      expect(content, contains('首选 A009 节奏变速'));
    });

    test('手册含批次25 新症候 P022 完整定义', () {
      expect(kSyndromeManualContent, contains('### P022 节奏比例失衡症'));
      final content = getSyndromeContent(['P022']);
      expect(content, contains('### P022 节奏比例失衡症'));
      expect(content, contains('核心问题'));
      expect(content, contains('判断原则'));
      expect(content, contains('推荐教学动作'));
      expect(content, contains('首选 A009 节奏变速'));
    });

    test('手册含批次26 新症候 P023 完整定义', () {
      expect(kSyndromeManualContent, contains('### P023 设定矛盾症'));
      final content = getSyndromeContent(['P023']);
      expect(content, contains('### P023 设定矛盾症'));
      expect(content, contains('核心问题'));
      expect(content, contains('判断原则'));
      expect(content, contains('推荐教学动作'));
      expect(content, contains('首选 A013 情节复盘'));
    });

    test('getSyndromeContent 按 ID 提取单个症候', () {
      final content = getSyndromeContent(['P001']);
      expect(content, contains('### P001 情绪标签化'));
      expect(content, contains('核心问题'));
      // 只含 P001，不含 P002 定义
      expect(content, isNot(contains('### P002')));
      // header 存在
      expect(content, contains('活跃症候详细定义'));
    });

    test('getSyndromeContent 多症候拼接 + 空输入返回空', () {
      final content = getSyndromeContent(['P001', 'P003']);
      expect(content, contains('### P001 情绪标签化'));
      expect(content, contains('### P003 视角漂移'));
      expect(getSyndromeContent([]), isEmpty);
      expect(getSyndromeContent(['P999']), isEmpty);
    });

    test('getSyndromeContent 提取 P018（批次70 新症候）', () {
      final content = getSyndromeContent(['P018']);
      expect(content, contains('### P018 重复用词/基础语病'));
      expect(content, contains('核心问题'));
      expect(content, contains('判断原则'));
      expect(content, contains('推荐教学动作'));
    });
  });

  group('technique 知识库', () {
    test('索引内容完整（含 T001-T031 与映射表）', () {
      expect(kTechniqueIndexContent, startsWith('# SKILL: 写作技法速查表（精简版）'));
      for (final id in ['T001', 'T010', 'T020', 'T031']) {
        expect(kTechniqueIndexContent, contains('| $id |'), reason: '索引缺 $id');
      }
      // 症候→技法映射表
      expect(kTechniqueIndexContent, contains('| P001 | T001 动态描写公式'));
    });

    test('技法库内容完整（含 T001 与 T031）', () {
      expect(kTechniqueLibraryContent, startsWith('# SKILL: 写作技法库'));
      expect(kTechniqueLibraryContent, contains('### T001'));
      expect(kTechniqueLibraryContent, contains('### T031'));
    });

    test('getTechniqueContent 按技法 ID 提取', () {
      final content = getTechniqueContent(['T001']);
      expect(content, contains('### T001'));
      expect(content, isNot(contains('### T002')));
      expect(content, contains('聚焦技法详细内容'));
    });

    test('getTechniquesBySyndrome 返回首选 + 备选技法', () {
      // P001 → [T001, T002, T020]，取 T001 + T002
      final content = getTechniquesBySyndrome(['P001']);
      expect(content, contains('### T001'));
      expect(content, contains('### T002'));
      expect(content, isNot(contains('### T020')));
      expect(getTechniquesBySyndrome([]), isEmpty);
    });
  });

  group('chat_context_builder L3 接线', () {
    test('focus 症候注入完整 L3 定义 + 技法', () {
      final text = buildStructuredSyndromeContext(
        [
          ActiveSyndromeView(
            syndromeId: 'P001',
            syndromeName: '情绪标签化',
            severity: Severity.l2,
            confirmationStatus: ConfirmationStatus.confirmed,
          ),
        ],
        activeFocus: const ActiveFocusContext(
          focusId: 'P001',
          source: FocusSource.aiSuggested,
          reason: '测试',
        ),
      );
      // L3 症候完整定义
      expect(text, contains('### P001 情绪标签化'));
      expect(text, contains('核心问题'));
      // L3 技法（P001 → T001 动态描写公式 + T002 感官交织法）
      expect(text, contains('### T001'));
      expect(text, contains('### T002'));
      // 训练知识由 message_injector 独立注入；本断言仅守护
      // buildStructuredSyndromeContext 自身不拼训练知识，不代表训练知识整体不进 prompt。
      expect(text, isNot(contains('当前教学焦点的完整训练知识')));
      // 非 focus 简化注入不受影响
      final simplified = buildStructuredSyndromeContext(
        [
          ActiveSyndromeView(
            syndromeId: 'P006',
            syndromeName: '语言堆砌',
            severity: Severity.l2,
            confirmationStatus: ConfirmationStatus.confirmed,
          ),
        ],
        activeFocus: const ActiveFocusContext(
          focusId: 'P001',
          source: FocusSource.aiSuggested,
          reason: '测试',
        ),
      );
      expect(simplified, isNot(contains('### P006')));
    });

    test('focus 注入后非 focus 按剩余预算注入（预算 clamp 锚定）', () {
      final text = buildStructuredSyndromeContext(
        [
          ActiveSyndromeView(
            syndromeId: 'P001',
            syndromeName: '情绪标签化',
            severity: Severity.l2,
            confirmationStatus: ConfirmationStatus.confirmed,
          ),
          ActiveSyndromeView(
            syndromeId: 'P006',
            syndromeName: '语言堆砌',
            severity: Severity.l2,
            confirmationStatus: ConfirmationStatus.confirmed,
          ),
        ],
        activeFocus: const ActiveFocusContext(
          focusId: 'P001',
          source: FocusSource.aiSuggested,
          reason: '测试',
        ),
      );
      // focus 已消耗预算，非 focus P006 按剩余预算分级注入（极简/完整摘要）
      expect(text, contains('- P006 语言堆砌'));
    });
  });

  group('training 知识库（training-templates-v2）', () {
    test('完整知识库覆盖 P001-P020', () {
      expect(kTrainingFullKnowledge, startsWith('# SKILL: 写作问题教学知识库'));
      for (final id in kTrainingSyndromeIds) {
        expect(
          kTrainingFullKnowledge,
          contains('## $id '),
          reason: '缺 $id 教学知识',
        );
      }
      // 关键要素齐全
      expect(kTrainingFullKnowledge, contains('核心本质'));
      expect(kTrainingFullKnowledge, contains('教学要点'));
      expect(kTrainingFullKnowledge, contains('常见误区'));
      expect(kTrainingFullKnowledge, contains('严重度判断参考'));
    });

    test('getTrainingContent 提取单个症候', () {
      final content = getTrainingContent(['P001']);
      expect(content, contains('## P001 情绪标签化'));
      expect(content, contains('核心本质'));
      expect(content, contains('教学要点'));
      expect(content, contains('常见误区'));
      expect(content, isNot(contains('## P002')));
      expect(content, contains('当前教学焦点的完整训练知识'));
    });

    test('getTrainingContent 多症候 + 空输入', () {
      final content = getTrainingContent(['P001', 'P001']);
      expect(content, contains('## P001'));
      expect(content, contains('## P001'));
      expect(getTrainingContent([]), isEmpty);
      expect(getTrainingContent(['P999']), isEmpty);
    });
  });
}
