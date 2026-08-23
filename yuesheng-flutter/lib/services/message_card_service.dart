// ─────────────────────────────────────────────────────────────
// 消息卡片服务 — 确定性触发机制
// 复刻 yuesheng-android/src/services/message-card-service.ts
//
// 解决 AUDIT-REF-5：卡片触发不再依赖 AI 自然语言输出中的标记，
// 而是由系统事件确定性地插入消息卡片到消息流中。
//
// 已实现卡片类型：
//   - insertDiagnosisResultCard（诊断结果卡片）
//   - insertTeacherSuggestionCard（Teacher 建议卡片，D6）
//   - insertReferenceChangeCard / insertPhaseUpgradeCard（批次 9）
//   - partial_agreement / phase_summary / diagnosis_failed（批次 17，渲染层
//     三卡由 message_list 分派 + fromMessageContent 构造）
//   - insertOutlineConfirmationCard（大纲记忆确认卡片，批次73）
// 未实现卡片类型（implicit_user）延后到需要时再补。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/genui_parser.dart';

/// 诊断结果卡片 Payload
/// 真源：message-card-service.ts DiagnosisResultCardPayload
class DiagnosisResultCardPayload {
  final int syndromeCount;
  final List<DiagnosisSyndromeCard> syndromes;
  final List<String> suggestedActions;
  final double confidence;
  final String diagnosisId;

  const DiagnosisResultCardPayload({
    required this.syndromeCount,
    required this.syndromes,
    required this.suggestedActions,
    required this.confidence,
    required this.diagnosisId,
  });

  factory DiagnosisResultCardPayload.fromJson(Map<String, dynamic> json) {
    final syndromesRaw = json['syndromes'] as List<dynamic>? ?? [];
    final actionsRaw = json['suggestedActions'] as List<dynamic>? ?? [];
    return DiagnosisResultCardPayload(
      syndromeCount: (json['syndromeCount'] as num?)?.toInt() ?? 0,
      syndromes: syndromesRaw
          .map(
            (e) => DiagnosisSyndromeCard.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      suggestedActions: actionsRaw.map((e) => e.toString()).toList(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      diagnosisId: (json['diagnosisId'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'syndromeCount': syndromeCount,
    'syndromes': syndromes.map((s) => s.toJson()).toList(),
    'suggestedActions': suggestedActions,
    'confidence': confidence,
    'diagnosisId': diagnosisId,
  };
}

/// 诊断结果卡片中的症候项
class DiagnosisSyndromeCard {
  final String syndromeId;
  final String name;
  final String severity; // 'L1' | 'L2' | 'L3'
  final int evidenceCount;

  const DiagnosisSyndromeCard({
    required this.syndromeId,
    required this.name,
    required this.severity,
    required this.evidenceCount,
  });

  factory DiagnosisSyndromeCard.fromJson(Map<String, dynamic> json) {
    return DiagnosisSyndromeCard(
      syndromeId:
          (json['syndrome_id'] as String?) ??
          (json['syndromeId'] as String?) ??
          '',
      name: (json['name'] as String?) ?? '',
      severity: (json['severity'] as String?) ?? 'L1',
      evidenceCount:
          (json['evidence_count'] as num?)?.toInt() ??
          (json['evidenceCount'] as num?)?.toInt() ??
          0,
    );
  }

  Map<String, dynamic> toJson() => {
    'syndrome_id': syndromeId,
    'name': name,
    'severity': severity,
    'evidence_count': evidenceCount,
  };
}

/// 诊断完成后，确定性插入诊断结果卡片
///
/// 真源：message-card-service.ts insertDiagnosisResultCard
///
/// 在 commitDiagnosisWithHistory 成功后调用。
/// 卡片以 system 角色 + diagnosis_result 类型写入 messages 表，
/// content 为 JSON 字符串，渲染端按 message_type 分派到对应卡片组件。
Future<String> insertDiagnosisResultCard(
  SessionRepository sessionRepo,
  String sessionId,
  DiagnosisResultCardPayload payload,
) async {
  final messageId = await sessionRepo.addMessage(
    sessionId,
    'system',
    jsonEncode(payload.toJson()),
    messageType: 'diagnosis_result',
  );
  return messageId;
}

/// 诊断失败卡片 Payload
/// 真源：message-card-service.ts DiagnosisFailedCardPayload
class DiagnosisFailedCardPayload {
  final int failureCount;

  const DiagnosisFailedCardPayload({required this.failureCount});

  factory DiagnosisFailedCardPayload.fromJson(Map<String, dynamic> json) {
    return DiagnosisFailedCardPayload(
      failureCount: (json['failureCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'failureCount': failureCount};
}

/// 诊断失败时，确定性插入诊断失败卡片（assistant 角色）
///
/// 真源：message-card-service.ts insertDiagnosisFailedCard
Future<String> insertDiagnosisFailedCard(
  SessionRepository sessionRepo,
  String sessionId,
  int failureCount,
) async {
  final messageId = await sessionRepo.addMessage(
    sessionId,
    'assistant',
    jsonEncode(DiagnosisFailedCardPayload(failureCount: failureCount).toJson()),
    messageType: 'diagnosis_failed',
  );
  return messageId;
}

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

// ════════════ 引用变更卡片（批次 9：消息卡片渲染扩展）════════════

/// 引用变更卡片 Payload
/// 真源：message-card-service.ts ReferenceChangeCardPayload
class ReferenceChangeCardPayload {
  final String action; // 'set_primary' | 'add' | 'remove'
  final String refType; // 'manuscript' | 'chapter'
  final String refTitle;

  const ReferenceChangeCardPayload({
    required this.action,
    required this.refType,
    required this.refTitle,
  });

  factory ReferenceChangeCardPayload.fromJson(Map<String, dynamic> json) {
    return ReferenceChangeCardPayload(
      action: (json['action'] as String?) ?? 'add',
      refType: (json['refType'] as String?) ?? 'manuscript',
      refTitle: (json['refTitle'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'action': action,
    'refType': refType,
    'refTitle': refTitle,
  };
}

/// 引用变更时，确定性插入引用变更卡片
///
/// 真源：message-card-service.ts insertReferenceChangeCard
/// 在 ReferenceBar 设主/移除 / 引用选择器添加后调用。
Future<String> insertReferenceChangeCard(
  SessionRepository sessionRepo,
  String sessionId,
  ReferenceChangeCardPayload payload,
) async {
  final messageId = await sessionRepo.addMessage(
    sessionId,
    'system',
    jsonEncode(payload.toJson()),
    messageType: 'reference_change',
  );
  return messageId;
}

// ════════════ 阶段升级卡片（批次 9：消息卡片渲染扩展）════════════

/// 阶段升级卡片 Payload
/// 真源：message-card-service.ts PhaseUpgradeCardPayload
class PhaseUpgradeCardPayload {
  final String from; // TeachingPhase.value
  final String to; // TeachingPhase.value
  final String? reason;

  const PhaseUpgradeCardPayload({
    required this.from,
    required this.to,
    this.reason,
  });

  factory PhaseUpgradeCardPayload.fromJson(Map<String, dynamic> json) {
    return PhaseUpgradeCardPayload(
      from: (json['from'] as String?) ?? 'P0_ENGAGE',
      to: (json['to'] as String?) ?? 'P1_WORLD',
      reason: (json['reason'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    if (reason != null) 'reason': reason,
  };
}

/// 阶段变更时，确定性插入阶段升级卡片
///
/// 真源：message-card-service.ts insertPhaseUpgradeCard
/// 在 phase-mapper resolver 迁移阶段（from != to）后调用。
Future<String> insertPhaseUpgradeCard(
  SessionRepository sessionRepo,
  String sessionId,
  PhaseUpgradeCardPayload payload,
) async {
  final messageId = await sessionRepo.addMessage(
    sessionId,
    'system',
    jsonEncode(payload.toJson()),
    messageType: 'phase_upgrade',
  );
  return messageId;
}

// ════════════════ 部分认同卡片（批次 17：消息卡片类型）════════════

/// 部分认同卡片 Payload
/// 真源：message-card-service.ts PartialAgreementCardPayload
class PartialAgreementCardPayload {
  final String syndromeId;
  final String syndromeName;
  final String severity; // 'L1' | 'L2' | 'L3'

  const PartialAgreementCardPayload({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
  });

  factory PartialAgreementCardPayload.fromJson(Map<String, dynamic> json) {
    return PartialAgreementCardPayload(
      syndromeId: (json['syndromeId'] as String?) ?? '',
      syndromeName: (json['syndromeName'] as String?) ?? '',
      severity: (json['severity'] as String?) ?? 'L1',
    );
  }

  Map<String, dynamic> toJson() => {
    'syndromeId': syndromeId,
    'syndromeName': syndromeName,
    'severity': severity,
  };
}

/// 症候变化项（PhaseSummaryCard 症候变化列表单项）
/// 真源：message-card-service.ts PhaseSummaryCardPayload.syndromeChanges（SyndromeEvaluationDetail[]）
/// 卡片渲染仅使用 syndromeName + trend，其余字段解析时忽略。
class SyndromeChangeItem {
  final String syndromeId;
  final String syndromeName;
  final String trend; // 'improving' | 'stable' | 'worsening'

  const SyndromeChangeItem({
    required this.syndromeId,
    required this.syndromeName,
    required this.trend,
  });

  factory SyndromeChangeItem.fromJson(Map<String, dynamic> json) {
    return SyndromeChangeItem(
      syndromeId: (json['syndromeId'] as String?) ?? '',
      syndromeName: (json['syndromeName'] as String?) ?? '',
      trend: (json['trend'] as String?) ?? 'stable',
    );
  }

  Map<String, dynamic> toJson() => {
    'syndromeId': syndromeId,
    'syndromeName': syndromeName,
    'trend': trend,
  };
}

/// 阶段总结卡片 Payload
/// 真源：message-card-service.ts PhaseSummaryCardPayload
class PhaseSummaryCardPayload {
  final String result; // 'passed' | 'partial' | 'failed'
  final int resolvedSyndromeCount;
  final int trainingCount;
  final String trend; // 'improving' | 'stable' | 'worsening'
  final List<SyndromeChangeItem> syndromeChanges;

  const PhaseSummaryCardPayload({
    required this.result,
    required this.resolvedSyndromeCount,
    required this.trainingCount,
    required this.trend,
    required this.syndromeChanges,
  });

  factory PhaseSummaryCardPayload.fromJson(Map<String, dynamic> json) {
    final changesRaw = json['syndromeChanges'] as List<dynamic>? ?? [];
    return PhaseSummaryCardPayload(
      result: (json['result'] as String?) ?? 'partial',
      resolvedSyndromeCount:
          (json['resolvedSyndromeCount'] as num?)?.toInt() ?? 0,
      trainingCount: (json['trainingCount'] as num?)?.toInt() ?? 0,
      trend: (json['trend'] as String?) ?? 'stable',
      syndromeChanges: changesRaw
          .map(
            (e) => SyndromeChangeItem.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'result': result,
    'resolvedSyndromeCount': resolvedSyndromeCount,
    'trainingCount': trainingCount,
    'trend': trend,
    'syndromeChanges': syndromeChanges.map((s) => s.toJson()).toList(),
  };
}

/// 部分认同时，确定性插入部分认同卡片（assistant 角色）
///
/// 真源：message-card-service.ts insertPartialAgreementCard
/// 签名保持 RN 一致（syndromeId/syndromeName/severity 平铺传参）。
Future<String> insertPartialAgreementCard(
  SessionRepository sessionRepo,
  String sessionId,
  String syndromeId,
  String syndromeName,
  String severity,
) async {
  final messageId = await sessionRepo.addMessage(
    sessionId,
    'assistant',
    jsonEncode(
      PartialAgreementCardPayload(
        syndromeId: syndromeId,
        syndromeName: syndromeName,
        severity: severity,
      ).toJson(),
    ),
    messageType: 'partial_agreement',
  );
  return messageId;
}

/// 阶段总结时，确定性插入阶段总结卡片（assistant 角色）
///
/// 真源：message-card-service.ts insertPhaseSummaryCard
Future<String> insertPhaseSummaryCard(
  SessionRepository sessionRepo,
  String sessionId,
  PhaseSummaryCardPayload payload,
) async {
  final messageId = await sessionRepo.addMessage(
    sessionId,
    'assistant',
    jsonEncode(payload.toJson()),
    messageType: 'phase_summary',
  );
  return messageId;
}

// ════════════════ GenUI 卡片（B-1 GenUI v1）════════════════

/// GenUI 卡片 Payload（B-1）
///
/// 由 chat_service_send 解析 [YS_GENUI] 协议块并确定性插入。
/// content 为 JSON，渲染端按 message_type=genui 分派到 GenUICard。
class GenuiCardPayload {
  final List<GenUiComponent> components;

  const GenuiCardPayload({required this.components});

  factory GenuiCardPayload.fromJson(Map<String, dynamic> json) {
    final list = json['components'] as List<dynamic>? ?? [];
    return GenuiCardPayload(
      components: list.whereType<Map<String, dynamic>>().map((m) {
        final type = (m['type'] as String?) ?? '';
        final data = Map<String, dynamic>.from(m)..remove('type');
        return GenUiComponent(type: type, data: data);
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'components': components.map((c) => c.toJson()).toList(),
  };
}

/// GenUI 组件解析落库后，确定性插入 GenUI 卡片消息（B-1）
///
/// 卡片以 system 角色 + genui 类型写入 messages 表，
/// content 为 JSON 字符串，渲染端按 message_type 分派到 GenUICard。
Future<String> insertGenuiCard(
  SessionRepository sessionRepo,
  String sessionId,
  GenuiCardPayload payload,
) async {
  return sessionRepo.addMessage(
    sessionId,
    'system',
    jsonEncode(payload.toJson()),
    messageType: 'genui',
  );
}
