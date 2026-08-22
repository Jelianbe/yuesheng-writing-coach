// ─────────────────────────────────────────────────────────────
// message_card_service 主题分组拆分：message_card_service_system.dart（R-019 ≤300 行）
// 系统事件类卡片：引用变更/阶段升级/部分认同/阶段总结/GenUI 卡片及 payload。逐字迁移自 message_card_service.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'message_card_service.dart';
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
