// ─────────────────────────────────────────────────────────────
// MessageCardDispatcher — 消息卡片统一分派（批次5 5.1）
//
// 提取自 message_list.dart（L330-442）与 writing_coach_panel.dart
// （L671-828）两套重复分派逻辑，收敛为单一入口，防两处行为漂移。
//
// 返回 null 表示不命中任何结构化卡片，调用方回退 MessageBubble。
// 采纳按钮（suggestion 消息）经 onAdoptSuggestion 收敛，采纳动作
// 统一走 suggestion_adoption_service。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../types/display_types.dart';
import 'diagnosis_card.dart';
import 'diagnosis_failed_card.dart';
import 'evaluation_report_panel.dart';
import 'gen_ui_card.dart';
import 'message_bubble.dart';
import 'outline_confirmation_card.dart';
import '../features/chat/partial_agreement_card.dart';
import 'phase_summary_card.dart';
import 'phase_upgrade_card.dart';
import 'reference_change_card.dart';
import 'teacher_suggestion_card.dart';
import '../config/app_palette.dart';

/// 按 messageType 分派结构化消息卡片。
///
/// 命中返回卡片 widget（含统一纵向 2px 间距），未命中返回 null。
///
/// 参数：
///   [evaluationReport] 评估报告数据（assistant 消息且命中时渲染报告面板）
///   [onTeachPrinciple] Teacher 建议卡「教我原理」回调（参数 = 症候名）
///   [onDismissEvaluationReport] 关闭评估报告回调
///   [onOpenGrowth] 评估报告「查看成长记录」回调（E1-b②，非空才渲染入口）
///   [onAdoptSuggestion] suggestion 采纳回调（非空时 suggestion 消息显示采纳按钮）
///   [onContinueTraining] PhaseSummaryCard「继续训练」回调
///   [onViewProfile] PhaseSummaryCard「查看学员画像」回调
///   [onBackToChat] PhaseSummaryCard「返回对话」回调
///   [onAddContent] DiagnosisFailedCard「补充内容」回调
///   [onContinueChat] DiagnosisFailedCard「继续对话」回调
///   [onPartialAgreementSubmit] PartialAgreementCard「提交反馈/快速选项」回调
///   [onPartialAgreementSkip] PartialAgreementCard「跳过此症候」回调
Widget? dispatchMessageCard({
  required BuildContext context,
  required Message msg,
  required bool isStreamingBubble,
  EvaluationData? evaluationReport,
  ValueChanged<String>? onTeachPrinciple,
  VoidCallback? onDismissEvaluationReport,
  VoidCallback? onOpenGrowth,
  VoidCallback? onAdoptSuggestion,
  VoidCallback? onContinueTraining,
  VoidCallback? onViewProfile,
  VoidCallback? onBackToChat,
  VoidCallback? onAddContent,
  VoidCallback? onContinueChat,
  void Function(String feedback, String? quickOption)? onPartialAgreementSubmit,
  VoidCallback? onPartialAgreementSkip,
}) {
  if (isStreamingBubble) return null;
  final card = _cardForMessageType(
    msg,
    onTeachPrinciple: onTeachPrinciple,
    onPartialAgreementSubmit: onPartialAgreementSubmit,
    onPartialAgreementSkip: onPartialAgreementSkip,
    onContinueTraining: onContinueTraining,
    onViewProfile: onViewProfile,
    onBackToChat: onBackToChat,
    onAddContent: onAddContent,
    onContinueChat: onContinueChat,
  );
  if (card != null) return _wrapWithVerticalPadding(card);
  if (msg.role == 'assistant' && evaluationReport != null) {
    return _wrapWithVerticalPadding(
      _buildEvaluationReportPanel(
        evaluationReport,
        onDismissEvaluationReport,
        onOpenGrowth,
      ),
    );
  }
  if (msg.role == 'assistant' &&
      msg.messageType == 'suggestion' &&
      onAdoptSuggestion != null) {
    return _buildSuggestionAdoptCard(msg, context, onAdoptSuggestion);
  }
  return null;
}

Widget? _cardForMessageType(
  Message msg, {
  ValueChanged<String>? onTeachPrinciple,
  void Function(String feedback, String? quickOption)? onPartialAgreementSubmit,
  VoidCallback? onPartialAgreementSkip,
  VoidCallback? onContinueTraining,
  VoidCallback? onViewProfile,
  VoidCallback? onBackToChat,
  VoidCallback? onAddContent,
  VoidCallback? onContinueChat,
}) {
  return switch (msg.messageType) {
    'diagnosis_result' => DiagnosisCard.fromMessageContent(
      msg.content,
      sessionId: msg.sessionId,
    ),
    'teacher_suggestion' => _buildTeacherSuggestionCard(msg, onTeachPrinciple),
    'outline_confirmation' => OutlineConfirmationCard.fromMessageContent(
      msg.content,
    ),
    'reference_change' => ReferenceChangeCard.fromMessageContent(msg.content),
    'phase_upgrade' => PhaseUpgradeCard.fromMessageContent(msg.content),
    'partial_agreement' => _buildPartialAgreementCard(
      msg,
      onPartialAgreementSubmit,
      onPartialAgreementSkip,
    ),
    'phase_summary' => _buildPhaseSummaryCard(
      msg,
      onContinueTraining,
      onViewProfile,
      onBackToChat,
    ),
    'diagnosis_failed' => _buildDiagnosisFailedCard(
      msg,
      onAddContent,
      onContinueChat,
    ),
    'genui' => GenUICard.fromMessageContent(msg.content, messageId: msg.id),
    _ => null,
  };
}

Widget _wrapWithVerticalPadding(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
  child: child,
);

Widget _buildTeacherSuggestionCard(
  Message msg,
  ValueChanged<String>? onTeachPrinciple,
) => TeacherSuggestionCard.fromMessageContent(
  msg.content,
  onTeachPrinciple: onTeachPrinciple,
);

Widget _buildPartialAgreementCard(
  Message msg,
  void Function(String feedback, String? quickOption)? onSubmit,
  VoidCallback? onSkip,
) => PartialAgreementCard.fromMessageContent(
  msg.content,
  onSubmit: onSubmit,
  onSkip: onSkip,
);

Widget _buildPhaseSummaryCard(
  Message msg,
  VoidCallback? onContinueTraining,
  VoidCallback? onViewProfile,
  VoidCallback? onBackToChat,
) => PhaseSummaryCard.fromMessageContent(
  msg.content,
  onContinueTraining: onContinueTraining,
  onViewProfile: onViewProfile,
  onBackToChat: onBackToChat,
);

Widget _buildDiagnosisFailedCard(
  Message msg,
  VoidCallback? onAddContent,
  VoidCallback? onContinueChat,
) => DiagnosisFailedCard.fromMessageContent(
  msg.content,
  onAddContent: onAddContent,
  onContinueChat: onContinueChat,
);

Widget _buildEvaluationReportPanel(
  EvaluationData evaluation,
  VoidCallback? onDismiss,
  VoidCallback? onOpenGrowth,
) => EvaluationReportPanel(
  evaluation: evaluation,
  onDismiss: onDismiss,
  onOpenGrowth: onOpenGrowth,
);

Widget _buildSuggestionAdoptCard(
  Message msg,
  BuildContext context,
  VoidCallback onAdoptSuggestion,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MessageBubble(message: msg),
      Padding(
        padding: const EdgeInsets.only(left: 40, bottom: AppSpacing.sm),
        child: TextButton(
          onPressed: onAdoptSuggestion,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            '采纳',
            style: TextStyle(fontSize: 12, color: context.palette.primary),
          ),
        ),
      ),
    ],
  );
}
