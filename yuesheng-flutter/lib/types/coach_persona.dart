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
//  - [personaLayer] 为 D2 人设层文本，Phase 1 仅承载、不消费。
// ─────────────────────────────────────────────────────────────

import 'teaching_types.dart';

class CoachPersona {
  final String id;
  final String name;

  /// 一句话声音描述（选人卡副标题），如「温和，先肯定再给建议，适合刚起步」。
  final String label;

  /// 是否系统预设（true = 内置 doubao/yuesheng/sensei；false = 用户自建）。
  final bool isSystem;

  /// 兼容壳：系统预设必填；用户预设默认 [AttitudeLevel.doubao]（取色/取图标用）。
  final AttitudeLevel attitudeLevel;

  /// 态度/语气段正文（候选注入文本）。
  final String systemPromptFragment;

  /// D2 人设层文本（可选，Phase 1 不消费）。
  final String? personaLayer;

  /// 可选图标键（用户预设可自选图标）。
  final String? iconKey;

  const CoachPersona({
    required this.id,
    required this.name,
    required this.label,
    required this.isSystem,
    required this.attitudeLevel,
    required this.systemPromptFragment,
    this.personaLayer,
    this.iconKey,
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
  }) =>
      CoachPersona(
        id: id ?? this.id,
        name: name ?? this.name,
        label: label ?? this.label,
        isSystem: isSystem ?? this.isSystem,
        attitudeLevel: attitudeLevel ?? this.attitudeLevel,
        systemPromptFragment: systemPromptFragment ?? this.systemPromptFragment,
        personaLayer: personaLayer ?? this.personaLayer,
        iconKey: iconKey ?? this.iconKey,
      );
}
