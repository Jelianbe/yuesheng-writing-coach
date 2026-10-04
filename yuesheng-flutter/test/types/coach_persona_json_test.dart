// ─────────────────────────────────────────────────────────────
// coach_persona_json_test — 结构化字段 JSON 兼容（ADR-C132 批1）
//
// 覆盖：
//   1. 旧数据（无新字段）→ 全部默认 null，不破坏既有读取
//   2. 新字段序列化往返（含 bool false 与 null 的区别）
//   3. 与既有字段共存（旧键不丢）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/types/coach_persona.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('CoachPersona 结构化字段 JSON 兼容', () {
    test('旧 JSON（无新字段）→ 新字段全部 null', () {
      final p = CoachPersona.fromJson(const {
        'id': 'custom-1',
        'name': '我的教练',
        'label': '温和',
        'is_system': false,
        'attitude_level': 'doubao',
        'system_prompt_fragment': '你是一个陪练伙伴。',
        'direct_explain_threshold': 5,
      });
      expect(p.expressionDensity, isNull);
      expect(p.questionPreference, isNull);
      expect(p.bufferWordPreference, isNull);
      expect(p.emojiAllowed, isNull);
      expect(p.name, '我的教练');
      expect(p.attitudeLevel, AttitudeLevel.gentle);
    });

    test('legacy 兼容：旧版持久化值 attitude_level="doubao" → gentle（不迁移用户数据）', () {
      // 改名批次：旧版落库值仍是 'doubao'，读入必须映射到默认档 gentle，
      // 禁止改库结构 / 清用户数据（持久化兼容硬约束）。
      final p = CoachPersona.fromJson(const {
        'id': 'legacy-1',
        'name': '老用户',
        'label': '温和',
        'is_system': false,
        'attitude_level': 'doubao',
      });
      expect(p.attitudeLevel, AttitudeLevel.gentle);
      // fromString 直测：旧值 'doubao' → gentle；新值 'gentle' 正常解析。
      expect(AttitudeLevel.fromString('doubao'), AttitudeLevel.gentle);
      expect(AttitudeLevel.fromString('gentle'), AttitudeLevel.gentle);
      expect(AttitudeLevel.fromString('yuesheng'), AttitudeLevel.yuesheng);
      expect(AttitudeLevel.fromString('sensei'), AttitudeLevel.sensei);
      expect(AttitudeLevel.fromString(null), isNull);
      expect(AttitudeLevel.fromString('no-such-tier'), isNull);
    });

    test('新字段序列化往返（含 false 与 null 的区别）', () {
      const p = CoachPersona(
        id: 'custom-2',
        name: '直给型',
        label: '直接',
        isSystem: false,
        attitudeLevel: AttitudeLevel.sensei,
        systemPromptFragment: '你是严格教练。',
        expressionDensity: 'high',
        questionPreference: 'direct',
        bufferWordPreference: 'none',
        emojiAllowed: false,
      );
      final json = p.toJson();
      expect(json['expression_density'], 'high');
      expect(json['question_preference'], 'direct');
      expect(json['buffer_word_preference'], 'none');
      expect(json['emoji_allowed'], false);

      final round = CoachPersona.fromJson(json);
      expect(round.expressionDensity, 'high');
      expect(round.questionPreference, 'direct');
      expect(round.bufferWordPreference, 'none');
      expect(round.emojiAllowed, isFalse);
      expect(round.attitudeLevel, AttitudeLevel.sensei);
    });

    test('null 字段序列化为 null 键（不写默认值）', () {
      const p = CoachPersona(
        id: 'custom-3',
        name: '默认型',
        label: '默认',
        isSystem: false,
        attitudeLevel: AttitudeLevel.gentle,
        systemPromptFragment: '',
      );
      final json = p.toJson();
      expect(json['expression_density'], isNull);
      expect(json['emoji_allowed'], isNull);
    });

    test('copyWith 可局部更新结构化字段且不丢其他字段', () {
      const p = CoachPersona(
        id: 'custom-4',
        name: '旧名',
        label: '旧',
        isSystem: false,
        attitudeLevel: AttitudeLevel.gentle,
        systemPromptFragment: '旧片段',
        expressionDensity: 'low',
      );
      final updated = p.copyWith(questionPreference: 'question');
      expect(updated.questionPreference, 'question');
      expect(updated.expressionDensity, 'low');
      expect(updated.name, '旧名');
      expect(updated.systemPromptFragment, '旧片段');
    });
  });
}
