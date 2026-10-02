// ─────────────────────────────────────────────────────────────
// CoachPersona — 教练人格数据模型（D1 用户自定义人格 / D2 人设层 共用主类型）
//
// 设计约束见 .ai/reports/2026-09-27-D-vision-design.md §2：
//  - 系统预设（doubao/yuesheng/sensei）映射回 [AttitudeLevel] 兼容壳，
//    颜色/图标沿用旧枚举（见 coach_selector_card._attitudeColor）；
//  - 用户预设走 app_state KV `coach_personas_custom`（JSON 数组，零迁移，
//    见 app_state_repository.dart）；
//  - [systemPromptFragment] 为注入 chat_context_builder 态度段的候选文本，
//    Phase 2 才接快照（当前系统预设注入仍由 skill_prompt_anchor 快照锁守护）；
//  - [personaLayer] 为 D2 人设层文本（可选）。用户预设激活且非空时由
//    skill_dispatcher 叠加注入（见 .ai/reports/2026-09-27-D-vision-design.md §2）。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart';
import 'teaching_types.dart';

class CoachPersona {
  final String id;
  final String name;

  /// 一句话语气描述（选人卡副标题），如「温和，先肯定再给建议，适合刚起步」。
  final String label;

  /// 是否系统预设（true = 内置 doubao/yuesheng/sensei；false = 用户自建）。
  final bool isSystem;

  /// 兼容壳：系统预设必填；用户预设默认 [AttitudeLevel.doubao]（取色/取图标用）。
  final AttitudeLevel attitudeLevel;

  /// 态度/语气段正文（候选注入文本）。
  final String systemPromptFragment;

  /// D2 人设层文本（可选）。用户预设激活且非空时由 skill_dispatcher 叠加注入。
  final String? personaLayer;

  /// 可选图标键（用户预设可自选图标）。
  final String? iconKey;

  /// Direct-explain threshold (Part A): when a diagnosis returns more syndromes
  /// than this value, explain all of them directly this turn instead of picking
  /// one focus / applying the selected teaching method. Default 5.
  final int directExplainThreshold;

  /// ── ADR-C132 结构化人格字段（批 1 数据层，批 2 注入链消费）──
  /// 全部可空 = 「不覆盖，沿用系统档 / 全局默认」。
  /// 用户预设激活且非空时，由 skill_dispatcher 组装为结构化约束注入
  /// （软风格层倾向声明；全局教学方式开关仍为裁决者，ADR-C132 §5）。

  /// 表达密度档：'low' | 'medium' | 'high'（null = 不覆盖）。
  final String? expressionDensity;

  /// 提问直给偏好：'question' | 'direct'（null = 不覆盖；注入层倾向，
  /// 不改全局教学方式开关裁决权）。
  final String? questionPreference;

  /// 缓冲词偏好：'none' | 'light' | 'warm'（null = 不覆盖）。
  final String? bufferWordPreference;

  /// 是否允许 emoji（null = 不覆盖，沿用系统档）。
  final bool? emojiAllowed;

  const CoachPersona({
    required this.id,
    required this.name,
    required this.label,
    required this.isSystem,
    required this.attitudeLevel,
    required this.systemPromptFragment,
    this.personaLayer,
    this.iconKey,
    this.directExplainThreshold = kDefaultDirectExplainThreshold,
    this.expressionDensity,
    this.questionPreference,
    this.bufferWordPreference,
    this.emojiAllowed,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'label': label,
    'is_system': isSystem,
    'attitude_level': attitudeLevel.value,
    'system_prompt_fragment': systemPromptFragment,
    'persona_layer': personaLayer,
    'icon_key': iconKey,
    'direct_explain_threshold': directExplainThreshold,
    'expression_density': expressionDensity,
    'question_preference': questionPreference,
    'buffer_word_preference': bufferWordPreference,
    'emoji_allowed': emojiAllowed,
  };

  factory CoachPersona.fromJson(Map<String, dynamic> json) {
    final level =
        AttitudeLevel.fromString(json['attitude_level'] as String?) ??
        AttitudeLevel.doubao;
    return CoachPersona(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      isSystem: (json['is_system'] as bool?) ?? false,
      attitudeLevel: level,
      systemPromptFragment: (json['system_prompt_fragment'] as String?) ?? '',
      personaLayer: json['persona_layer'] as String?,
      iconKey: json['icon_key'] as String?,
      directExplainThreshold:
          (json['direct_explain_threshold'] as num?)?.toInt() ?? 5,
      expressionDensity: json['expression_density'] as String?,
      questionPreference: json['question_preference'] as String?,
      bufferWordPreference: json['buffer_word_preference'] as String?,
      emojiAllowed: json['emoji_allowed'] as bool?,
    );
  }

  CoachPersona copyWith({
    String? id,
    String? name,
    String? label,
    bool? isSystem,
    AttitudeLevel? attitudeLevel,
    String? systemPromptFragment,
    String? personaLayer,
    String? iconKey,
    int? directExplainThreshold,
    String? expressionDensity,
    String? questionPreference,
    String? bufferWordPreference,
    bool? emojiAllowed,
  }) => CoachPersona(
    id: id ?? this.id,
    name: name ?? this.name,
    label: label ?? this.label,
    isSystem: isSystem ?? this.isSystem,
    attitudeLevel: attitudeLevel ?? this.attitudeLevel,
    systemPromptFragment: systemPromptFragment ?? this.systemPromptFragment,
    personaLayer: personaLayer ?? this.personaLayer,
    iconKey: iconKey ?? this.iconKey,
    directExplainThreshold:
        directExplainThreshold ?? this.directExplainThreshold,
    expressionDensity: expressionDensity ?? this.expressionDensity,
    questionPreference: questionPreference ?? this.questionPreference,
    bufferWordPreference: bufferWordPreference ?? this.bufferWordPreference,
    emojiAllowed: emojiAllowed ?? this.emojiAllowed,
  );
}
