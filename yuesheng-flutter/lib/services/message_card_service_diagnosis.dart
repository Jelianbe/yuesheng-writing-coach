// ─────────────────────────────────────────────────────────────
// message_card_service 主题分组拆分：message_card_service_diagnosis.dart（R-019 ≤300 行）
// 诊断类卡片：DiagnosisResultCardPayload/DiagnosisSyndromeCard/insertDiagnosisResultCard/DiagnosisFailedCardPayload/insertDiagnosisFailedCard。逐字迁移自 message_card_service.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'message_card_service.dart';
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

