// ─────────────────────────────────────────────────────────────
// message_card_service 主题分组拆分：message_card_service_teaching.dart（R-019 ≤300 行）
// 教学建议类卡片：TeacherSuggestionCardPayload/insertTeacherSuggestionCard/OutlineConfirmationPayload/OutlineImpressionPayload/insertOutlineConfirmationCard。逐字迁移自 message_card_service.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'message_card_service.dart';
/// Teacher 建议卡片 Payload（D6）
///
/// 真源：message-card-service.ts TeacherSuggestionCardPayload
/// targetSyndromeName 存症候名称而非代号（记忆硬约束：显示症候名称而非代号）
class TeacherSuggestionCardPayload {
  final String suggestionId;
  final String teachingDecision; // 'guide' | 'train'
  final String naturalLanguage;
  final String taskType; // 'rewrite' | 'analyze' | 'compare' | 'generate'
  final String taskDescription;
  final String difficulty; // 'easy' | 'medium' | 'hard'
  final List<String> evaluationCriteria;
  final String? targetSyndromeId;
  final String? targetSyndromeName;
  final String source; // 'editor' | 'diagnosis'

  /// 批次63（B62d）：位置清单（每项 = 段落位置 + 原文摘录），供「标注位置自查」
  final List<String> locationMarks;

  const TeacherSuggestionCardPayload({
    required this.suggestionId,
    required this.teachingDecision,
    required this.naturalLanguage,
    required this.taskType,
    required this.taskDescription,
    required this.difficulty,
    required this.evaluationCriteria,
    this.targetSyndromeId,
    this.targetSyndromeName,
    required this.source,
    this.locationMarks = const [],
  });

  factory TeacherSuggestionCardPayload.fromJson(Map<String, dynamic> json) {
    final criteriaRaw = json['evaluationCriteria'] as List<dynamic>? ?? [];
    final locationRaw = json['locationMarks'] as List<dynamic>? ?? [];
    return TeacherSuggestionCardPayload(
      suggestionId: (json['suggestionId'] as String?) ?? '',
      teachingDecision: (json['teachingDecision'] as String?) ?? 'guide',
      naturalLanguage: (json['naturalLanguage'] as String?) ?? '',
      taskType: (json['taskType'] as String?) ?? '',
      taskDescription: (json['taskDescription'] as String?) ?? '',
      difficulty: (json['difficulty'] as String?) ?? '',
      evaluationCriteria: criteriaRaw.map((e) => e.toString()).toList(),
      targetSyndromeId: (json['targetSyndromeId'] as String?),
      targetSyndromeName: (json['targetSyndromeName'] as String?),
      source: (json['source'] as String?) ?? 'diagnosis',
      locationMarks: locationRaw.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'suggestionId': suggestionId,
    'teachingDecision': teachingDecision,
    'naturalLanguage': naturalLanguage,
    'taskType': taskType,
    'taskDescription': taskDescription,
    'difficulty': difficulty,
    'evaluationCriteria': evaluationCriteria,
    'targetSyndromeId': targetSyndromeId,
    'targetSyndromeName': targetSyndromeName,
    'source': source,
    'locationMarks': locationMarks,
  };
}

/// Teacher 建议落库成功后，确定性插入建议卡片消息（D6）
///
/// 卡片以 system 角色 + teacher_suggestion 类型写入 messages 表，
/// content 为 JSON 字符串，渲染端按 message_type 分派到 TeacherSuggestionCard。
Future<String> insertTeacherSuggestionCard(
  SessionRepository sessionRepo,
  String sessionId,
  TeacherSuggestionCardPayload payload,
) async {
  final messageId = await sessionRepo.addMessage(
    sessionId,
    'system',
    jsonEncode(payload.toJson()),
    messageType: 'teacher_suggestion',
  );
  return messageId;
}

/// 大纲确认卡片 Payload（批次73）
///
/// 一个实体一张卡；impressions 为该实体本次新写入的 pending 印象。
/// content 为 JSON，渲染端按 message_type=outline_confirmation 分派。
class OutlineConfirmationPayload {
  final String confirmationId;
  final String entityId;
  final String entityType; // character | setting | plot
  final String entityKey; // 规范名
  final bool isNewEntity;
  final List<OutlineImpressionPayload> impressions;

  const OutlineConfirmationPayload({
    required this.confirmationId,
    required this.entityId,
    required this.entityType,
    required this.entityKey,
    required this.isNewEntity,
    required this.impressions,
  });

  factory OutlineConfirmationPayload.fromJson(Map<String, dynamic> json) {
    final impressionsRaw = json['impressions'] as List<dynamic>? ?? [];
    return OutlineConfirmationPayload(
      confirmationId: (json['confirmationId'] as String?) ?? '',
      entityId: (json['entityId'] as String?) ?? '',
      entityType: (json['entityType'] as String?) ?? 'character',
      entityKey: (json['entityKey'] as String?) ?? '',
      isNewEntity: (json['isNewEntity'] as bool?) ?? false,
      impressions: impressionsRaw
          .whereType<Map<String, dynamic>>()
          .map(OutlineImpressionPayload.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'confirmationId': confirmationId,
    'entityId': entityId,
    'entityType': entityType,
    'entityKey': entityKey,
    'isNewEntity': isNewEntity,
    'impressions': impressions.map((i) => i.toJson()).toList(),
  };
}

/// 确认卡内单条印象（pending 态）
class OutlineImpressionPayload {
  final String id;
  final String text;
  final String? conflictWith; // 与已有印象矛盾（非空 = 冲突二选一）

  const OutlineImpressionPayload({
    required this.id,
    required this.text,
    this.conflictWith,
  });

  factory OutlineImpressionPayload.fromJson(Map<String, dynamic> json) {
    return OutlineImpressionPayload(
      id: (json['id'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
      conflictWith: json['conflictWith'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'conflictWith': conflictWith,
  };
}

/// 大纲确认落库后，确定性插入确认卡片消息（批次73）
///
/// 卡片以 system 角色 + outline_confirmation 类型写入 messages 表，
/// content 为 JSON 字符串，渲染端按 message_type 分派到 OutlineConfirmationCard。
Future<String> insertOutlineConfirmationCard(
  SessionRepository sessionRepo,
  String sessionId,
  OutlineConfirmationPayload payload,
) async {
  final messageId = await sessionRepo.addMessage(
    sessionId,
    'system',
    jsonEncode(payload.toJson()),
    messageType: 'outline_confirmation',
  );
  return messageId;
}

