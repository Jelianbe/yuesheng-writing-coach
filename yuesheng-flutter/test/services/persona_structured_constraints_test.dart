// persona_structured_constraints_test — 结构化约束组装（ADR-C132 批2）
//
// 覆盖：四类字段 → 约束段映射；全空 → 空串（无注入块）；
// 非法值静默忽略（防御性，不因脏数据让注入链失败）；
// 提问直给偏好的约束文本声明「遵守教学方式开关裁决」（倾向层不越权）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/persona_structured_constraints.dart';
import 'package:writingcoach/types/coach_persona.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  CoachPersona p({
    String? expressionDensity,
    String? questionPreference,
    String? bufferWordPreference,
    bool? emojiAllowed,
  }) => CoachPersona(
    id: 'c',
    name: 'n',
    label: 'l',
    isSystem: false,
    attitudeLevel: AttitudeLevel.gentle,
    systemPromptFragment: 'f',
    expressionDensity: expressionDensity,
    questionPreference: questionPreference,
    bufferWordPreference: bufferWordPreference,
    emojiAllowed: emojiAllowed,
  );

  group('buildStructuredConstraints 字段映射', () {
    test('#1 全空 → 空串（不产生注入块）', () {
      expect(buildStructuredConstraints(p()), isEmpty);
    });

    test('#2 表达密度三档逐档命中', () {
      expect(
        buildStructuredConstraints(p(expressionDensity: 'low')),
        contains('表达密度：简洁克制'),
      );
      expect(
        buildStructuredConstraints(p(expressionDensity: 'medium')),
        contains('表达密度：适中'),
      );
      expect(
        buildStructuredConstraints(p(expressionDensity: 'high')),
        contains('表达密度：可以铺陈充分'),
      );
    });

    test('#3 提问直给两档 + 不越权声明（遵守教学方式开关裁决）', () {
      expect(
        buildStructuredConstraints(p(questionPreference: 'question')),
        contains('遵守教学方式开关的裁决'),
      );
      expect(
        buildStructuredConstraints(p(questionPreference: 'direct')),
        contains('倾向直接指出问题与方向'),
      );
    });

    test('#4 缓冲词三档', () {
      expect(
        buildStructuredConstraints(p(bufferWordPreference: 'none')),
        contains('避免使用'),
      );
      expect(
        buildStructuredConstraints(p(bufferWordPreference: 'light')),
        contains('克制使用'),
      );
      expect(
        buildStructuredConstraints(p(bufferWordPreference: 'warm')),
        contains('温和缓冲词'),
      );
    });

    test('#5 emoji true / false / null 三态', () {
      expect(
        buildStructuredConstraints(p(emojiAllowed: true)),
        contains('可以少量使用'),
      );
      expect(
        buildStructuredConstraints(p(emojiAllowed: false)),
        contains('emoji：不使用'),
      );
      expect(
        buildStructuredConstraints(p(emojiAllowed: null)),
        isNot(contains('emoji')),
      );
    });

    test('#6 非法值静默忽略（不抛错、不产出该行）', () {
      final out = buildStructuredConstraints(
        p(expressionDensity: 'loud', bufferWordPreference: 'extreme'),
      );
      expect(out, isEmpty);
    });

    test('#7 多字段合并为多行（\n 分隔，顺序固定）', () {
      final out = buildStructuredConstraints(
        p(expressionDensity: 'high', questionPreference: 'question'),
      );
      final lines = out.split('\n');
      expect(lines, hasLength(2));
      expect(lines[0], contains('表达密度'));
      expect(lines[1], contains('提问直给偏好'));
    });
  });

  group('kPersonaRedLine', () {
    test('#8 边界句含 R-009 核心（不替写 / 不替决定）+ 直给边界（禁成段成品与打分）', () {
      expect(kPersonaRedLine, contains('不替学员写句子'));
      expect(kPersonaRedLine, contains('不替学员做决定'));
      expect(kPersonaRedLine, contains('禁成段成品与打分'));
      expect(kPersonaRedLine, contains('示范单句受限'));
      expect(kPersonaRedLine, contains('为说明改法可给单句示范'));
      expect(kPersonaRedLine, contains('不改全段'));
      expect(kPersonaRedLine, contains('不替写成品段落'));
      // F-1 口径（ADR-C134）：旧「禁成句与打分」字样已废，注入链不得再出现
      //（示范单句 ≠ 替写，直给判断禁成句的语义由「禁成段成品」承接）。
      expect(kPersonaRedLine, isNot(contains('禁成句与打分')));
    });
  });
}
