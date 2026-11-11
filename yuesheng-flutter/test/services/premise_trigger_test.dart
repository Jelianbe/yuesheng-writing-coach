// T-20261110-13 · premise_trigger 测试（报批稿 R1/R2/R6 判据 + U3 签核自证）
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/intent_classifier.dart';
import 'package:writingcoach/services/premise_trigger.dart';

void main() {
  group('premise_trigger · 触发判据', () {
    // R1：命中轮注入串含 P031 段标记 + 四段构成锚（N1 可达）
    test('R1 · ask + 题材词 ⇒ 注入串含 P031 标记与四段锚', () {
      final note = buildPremiseTeachingInjection(
        intent: UserIntent.ask,
        typedText: '我想聊聊这本书的题材定位',
      );
      expect(note, isNotNull);
      // R1 锚：P031 段标记（来自训练KB节标题）
      expect(note!, contains('P031'));
      // ① 头注锚
      expect(note, contains('这是前提层教学对话，不是文本诊断'));
      // ② 手册精简段锚
      expect(note, contains('赛道定位'));
      expect(note, contains('推荐教学动作'));
      // ③ 训练KB 段锚（提取自 kTrainingFullKnowledge）
      expect(note, contains('核心本质'));
      expect(note, contains('教学素材库'));
      // ④ 边界句锚
      expect(note, contains('不替学员选题材、选赛道、定读者'));
    });

    // R2：诊断链路意图（compose）优先 ⇒ 抑制（G1）
    test('R2 · compose + 题材词 ⇒ null（诊断优先）', () {
      expect(
        buildPremiseTeachingInjection(
          intent: UserIntent.compose,
          typedText: '帮我看看这本书的题材定位行不行',
        ),
        isNull,
      );
    });

    // R6：键入文本不含关键词 ⇒ null（只判键入文本，引用文本由调用方排除）
    test('R6 · 无关键词 ⇒ null；关键词集逐词命中', () {
      expect(
        buildPremiseTeachingInjection(
          intent: UserIntent.ask,
          typedText: '这段对话写得自然吗',
        ),
        isNull,
      );
      // 关键词集 K 终稿 11 词逐词可命中
      for (final k in kPremiseTopicKeywords) {
        expect(premiseTopicHit('关于$k的问题'), isTrue, reason: '关键词 $k');
      }
      expect(premiseTopicHit('今天天气不错'), isFalse);
    });

    // revise 轮触发（设计稿边界表：「这段题材感不对怎么改」起步判据不排除）
    test('revise 轮命中 ⇒ 注入（误报代价可控）', () {
      expect(
        buildPremiseTeachingInjection(
          intent: UserIntent.revise,
          typedText: '这段题材感不对怎么改',
        ),
        isNotNull,
      );
    });
  });

  group('premise_trigger · KB 提取边界与 U3 签核自证', () {
    test('KB 段提取不串段（P031 节完整、不含 P032）', () {
      final note = buildPremiseTeachingInjection(
        intent: UserIntent.ask,
        typedText: '题材',
      )!;
      // P031 节标题存在（提取起点正确）
      expect(note, contains('## P031 题材边界感缺失'));
      // 下一节 P032 未被串入（提取终点正确）
      expect(note, isNot(contains('## P032')));
      // 节尾内容在（教学素材库四条的最后一条）
      expect(note, contains('读者画像模板'));
    });

    test('U3 裁定自证：手册精简段已删诊断口吻段', () {
      final note = buildPremiseTeachingInjection(
        intent: UserIntent.ask,
        typedText: '题材',
      )!;
      // 删「严重度判断」段（L1/L2/L3 判级指令不在精简段）
      expect(note, isNot(contains('**严重度判断**')));
      // 删「诊断锚点示例」段（判定口吻 few-shot 不在）
      expect(note, isNot(contains('判定：P031')));
      // 删 position_sensitivity（诊断面专用标记）
      expect(note, isNot(contains('position_sensitivity')));
    });

    test('G3：注入无冷却（同输入重复调用结果一致）', () {
      final a = buildPremiseTeachingInjection(
        intent: UserIntent.ask,
        typedText: '聊聊题材定位',
      );
      final b = buildPremiseTeachingInjection(
        intent: UserIntent.ask,
        typedText: '聊聊题材定位',
      );
      expect(a, equals(b));
    });
  });
}
