// ─────────────────────────────────────────────────────────────
// AttitudeAdvisor — 态度建议引擎（缺口清单 A 类：态度建议横幅）
// 真源：yuesheng-android/src/services/attitude-advisor.service.ts
//
// 纯函数：根据当前态度档位 + 教学阶段 + 最新诊断 + 消息数 +
// 反馈连续次数 + 冷却时间，决定是否建议升级/降级态度档位。
// ─────────────────────────────────────────────────────────────

import '../config/shared_constants.dart';
import '../types/teaching_types.dart';

/// 态度建议（对齐 RN AttitudeSuggestion）
class AttitudeSuggestion {
  final String direction; // 'upgrade' | 'downgrade'
  final AttitudeLevel targetLevel;
  final String reason;

  const AttitudeSuggestion({
    required this.direction,
    required this.targetLevel,
    required this.reason,
  });
}

/// 档位顺序（对齐 RN ATTITUDE_ORDER）：doubao → yuesheng → sensei
const List<AttitudeLevel> attitudeOrder = [
  AttitudeLevel.doubao,
  AttitudeLevel.yuesheng,
  AttitudeLevel.sensei,
];

/// 症候严重度排名（对齐 RN severity L3→3 / L2→2 / L1→1）
int _severityRank(Severity s) => switch (s) {
  Severity.l3 => 3,
  Severity.l2 => 2,
  Severity.l1 => 1,
};

/// 计算态度建议（复刻 RN suggestAttitudeAdjustment）
///
/// - `syndromes`：最新诊断的症候严重度列表（空 = 无诊断）
/// - `messageCount`：会话消息总数
/// - 冷却期内或消息数不足时返回 null
AttitudeSuggestion? suggestAttitudeAdjustment({
  required AttitudeLevel currentAttitude,
  required TeachingPhase currentPhase,
  List<Severity> syndromes = const [],
  required int messageCount,
  int consecutivePositiveFeedback = 0,
  int consecutiveNegativeFeedback = 0,
  int? lastSuggestionTime,
  int? now,
}) {
  final currentTime = now ?? DateTime.now().millisecondsSinceEpoch;

  if (messageCount < AttitudeThresholds.minMessageCount) return null;

  if (lastSuggestionTime != null &&
      currentTime - lastSuggestionTime <
          AttitudeThresholds.suggestionCooldownMs) {
    return null;
  }

  final currentIndex = attitudeOrder.indexOf(currentAttitude);

  final avgSeverity = syndromes.isEmpty
      ? 0.0
      : syndromes.map(_severityRank).reduce((a, b) => a + b) / syndromes.length;

  final isHighPhase =
      currentPhase == TeachingPhase.p2PracticeLoop ||
      currentPhase == TeachingPhase.p3Training;

  final positiveFeedbackEnough =
      consecutivePositiveFeedback >= AttitudeThresholds.positiveFeedbackUpgradeCount;
  final negativeFeedbackEnough =
      consecutiveNegativeFeedback >= AttitudeThresholds.negativeFeedbackDowngradeCount;

  // 升级（当前档位非最高）：问题多且严重，或学员积极跟上（正反馈）
  if (currentIndex < attitudeOrder.length - 1) {
    final canUpgrade =
        (isHighPhase &&
            avgSeverity >= AttitudeThresholds.upgradeSeverityThreshold &&
            syndromes.length >= AttitudeThresholds.upgradeSyndromeCount) ||
        positiveFeedbackEnough ||
        (messageCount >= AttitudeThresholds.upgradeMessageCountHigh &&
            isHighPhase &&
            avgSeverity >= AttitudeThresholds.upgradeSeverityThresholdHigh);

    if (canUpgrade) {
      final target = attitudeOrder[currentIndex + 1];
      return AttitudeSuggestion(
        direction: 'upgrade',
        targetLevel: target,
        reason: _generateUpgradeReason(
          target,
          syndromes,
          avgSeverity,
          isHighPhase,
          viaPositiveFeedback: positiveFeedbackEnough,
        ),
      );
    }
  }

  // 降级（当前档位非最低）：问题少且轻，或用户挫败/负反馈（对齐教学策略"用户挫败降档"）
  if (currentIndex > 0) {
    final canDowngrade =
        negativeFeedbackEnough ||
        (avgSeverity <= AttitudeThresholds.downgradeSeverityThreshold &&
            syndromes.length <= AttitudeThresholds.downgradeSyndromeCount &&
            messageCount >= AttitudeThresholds.downgradeMessageCount);

    if (canDowngrade) {
      final target = attitudeOrder[currentIndex - 1];
      return AttitudeSuggestion(
        direction: 'downgrade',
        targetLevel: target,
        reason: _generateDowngradeReason(
          target,
          syndromes,
          avgSeverity,
          viaNegativeFeedback: negativeFeedbackEnough,
        ),
      );
    }
  }

  return null;
}

/// 从消息摘要计算态度降档信号（B4 接线核心）。
///
/// 返回应传给 [suggestAttitudeAdjustment] 的 `consecutiveNegativeFeedback` 值：
/// - 从最新用户消息向前，连续命中负反馈关键词的条数（[containsNegativeFeedback]）；
/// - 若最新用户消息含安全词「轻一点」降档请求（[isSafetyWordRequest]），
///   强制达到降档阈值（对齐教练哲学：安全词无条件降档）。
///
/// 用 record 传参避免引入数据库层耦合。
int computeAttitudeDowngradeSignal(
  List<({String role, String content})> messages,
) {
  int consecutiveNegative = 0;
  for (final m in messages.reversed) {
    if (m.role != 'user') continue;
    if (containsNegativeFeedback(m.content)) {
      consecutiveNegative++;
    } else {
      break;
    }
  }

  final latestUser =
      messages.reversed.where((m) => m.role == 'user').firstOrNull;
  if (latestUser != null && isSafetyWordRequest(latestUser.content)) {
    consecutiveNegative = AttitudeThresholds.negativeFeedbackDowngradeCount;
  }

  return consecutiveNegative;
}

String _generateUpgradeReason(
  AttitudeLevel target,
  List<Severity> syndromes,
  double avgSeverity,
  bool isHighPhase, {
  bool viaPositiveFeedback = false,
}) {
  final targetLabel = getAttitudeLabel(target);
  final reasons = <String>[];

  if (syndromes.length >= 2) {
    reasons.add('当前发现 ${syndromes.length} 个写作问题');
  }
  if (avgSeverity >= 2) {
    reasons.add('问题严重度偏高');
  }
  if (isHighPhase) {
    reasons.add('已进入训练阶段');
  }
  if (viaPositiveFeedback && reasons.isEmpty) {
    reasons.add('最近几轮你反馈积极，跟得上节奏');
  }

  final reasonText = reasons.isNotEmpty ? reasons.join('，') : '学习状态良好';
  final stricter = target == AttitudeLevel.sensei ? '严格专业' : '有针对性';
  return '$reasonText，建议切换到「$targetLabel」模式，获得更$stricter的指导。';
}

String _generateDowngradeReason(
  AttitudeLevel target,
  List<Severity> syndromes,
  double avgSeverity, {
  bool viaNegativeFeedback = false,
}) {
  final targetLabel = getAttitudeLabel(target);
  final reasons = <String>[];

  if (viaNegativeFeedback) {
    reasons.add('你反馈了节奏或强度问题');
  }
  if (syndromes.length <= 1) {
    reasons.add('当前问题较少');
  }
  if (avgSeverity <= 1.2) {
    reasons.add('严重度较低');
  }

  final reasonText = reasons.isNotEmpty ? reasons.join('，') : '状态不错';
  return '$reasonText，建议切换到「$targetLabel」模式，保持轻松学习氛围。';
}

/// 档位展示名（对齐 RN getAttitudeLabel）
String getAttitudeLabel(AttitudeLevel level) => switch (level) {
  AttitudeLevel.doubao => '豆包',
  AttitudeLevel.yuesheng => '月笙',
  AttitudeLevel.sensei => '老师',
};
