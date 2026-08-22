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
import 'partial_agreement_card.dart';
import 'phase_summary_card.dart';
import 'phase_upgrade_card.dart';
import 'reference_change_card.dart';
import 'teacher_suggestion_card.dart';

/// 按 messageType 分派结构化消息卡片。
///
/// 命中返回卡片 widget（含统一纵向 2px 间距），未命中返回 null。
///
/// 参数：
///   [evaluationReport] 评估报告数据（assistant 消息且命中时渲染报告面板）
///   [onTeachPrinciple] Teacher 建议卡「教我原理」回调（参数 = 症候名）
///   [onDismissEvaluationReport] 关闭评估报告回调
///   [onAdoptSuggestion] suggestion 采纳回调（非空时 suggestion 消息显示采纳按钮）
///   [onContinueTraining] PhaseSummaryCard「继续训练」回调
///   [onViewProfile] PhaseSummaryCard「查看学员画像」回调
///   [onBackToChat] PhaseSummaryCard「返回对话」回调
///   [onAddContent] DiagnosisFailedCard「补充内容」回调
///   [onContinueChat] DiagnosisFailedCard「继续对话」回调
///   [onPartialAgreementSubmit] PartialAgreementCard「提交反馈/快速选项」回调
///   [onPartialAgreementSkip] PartialAgreementCard「跳过此症候」回调
Widget? dispatchMessageCard({
  required Message msg,
  required bool isStreamingBubble,
  EvaluationData? evaluationReport,
  ValueChanged<String>? onTeachPrinciple,
  VoidCallback? onDismissEvaluationReport,
  VoidCallback? onAdoptSuggestion,
  VoidCallback? onContinueTraining,
  VoidCallback? onViewProfile,
  VoidCallback? onBackToChat,
  VoidCallback? onAddContent,
  VoidCallback? onContinueChat,
  void Function(String feedback, String? quickOption)? onPartialAgreementSubmit,
  VoidCallback? onPartialAgreementSkip,
}) {
  const verticalPadding = EdgeInsets.symmetric(vertical: 2);

  // D3：diagnosis_result → DiagnosisCard（结构化卡片，不包裹进气泡）
  if (!isStreamingBubble && msg.messageType == 'diagnosis_result') {
    return Padding(
      padding: verticalPadding,
      child: DiagnosisCard.fromMessageContent(
        msg.content,
        sessionId: msg.sessionId,
      ),
    );
  }

  // D6：teacher_suggestion → TeacherSuggestionCard（三按钮建议卡片）
  if (!isStreamingBubble && msg.messageType == 'teacher_suggestion') {
    return Padding(
      padding: verticalPadding,
      child: TeacherSuggestionCard.fromMessageContent(
        msg.content,
        onTeachPrinciple: onTeachPrinciple,
      ),
    );
  }

  // 批次73：outline_confirmation → 大纲记忆确认卡片
  if (!isStreamingBubble && msg.messageType == 'outline_confirmation') {
    return Padding(
      padding: verticalPadding,
      child: OutlineConfirmationCard.fromMessageContent(msg.content),
    );
  }

  // 批次9：引用变更卡片（展示型 system 卡片）
  if (!isStreamingBubble && msg.messageType == 'reference_change') {
    return Padding(
      padding: verticalPadding,
      child: ReferenceChangeCard.fromMessageContent(msg.content),
    );
  }

  // 批次9：阶段升级卡片（展示型 system 卡片）
  if (!isStreamingBubble && msg.messageType == 'phase_upgrade') {
    return Padding(
      padding: verticalPadding,
      child: PhaseUpgradeCard.fromMessageContent(msg.content),
    );
  }

  // 批次17：部分认同 / 阶段总结 / 诊断失败 三卡
  // 批次81：三卡回调接线（H1-H3）——由调用方传入真实回调，不再 `?? () {}` 兜底
  if (!isStreamingBubble && msg.messageType == 'partial_agreement') {
    return Padding(
      padding: verticalPadding,
      child: PartialAgreementCard.fromMessageContent(
        msg.content,
        onSubmit: onPartialAgreementSubmit,
        onSkip: onPartialAgreementSkip,
      ),
    );
  }

  if (!isStreamingBubble && msg.messageType == 'phase_summary') {
    return Padding(
      padding: verticalPadding,
      child: PhaseSummaryCard.fromMessageContent(
        msg.content,
        onContinueTraining: onContinueTraining,
        onViewProfile: onViewProfile,
        onBackToChat: onBackToChat,
      ),
    );
  }

  if (!isStreamingBubble && msg.messageType == 'diagnosis_failed') {
    return Padding(
      padding: verticalPadding,
      child: DiagnosisFailedCard.fromMessageContent(
        msg.content,
        onAddContent: onAddContent,
        onContinueChat: onContinueChat,
      ),
    );
  }

  // B-1：genui → GenUICard（GenUI 协议块渲染，diff/quiz 等教学交互组件）
  if (!isStreamingBubble && msg.messageType == 'genui') {
    return Padding(
      padding: verticalPadding,
      child: GenUICard.fromMessageContent(msg.content, messageId: msg.id),
    );
  }

  // T4：评估报告（assistant 消息 + reports 命中 → 渲染评估报告面板）
  if (!isStreamingBubble &&
      msg.role == 'assistant' &&
      evaluationReport != null) {
    return Padding(
      padding: verticalPadding,
      child: EvaluationReportPanel(
        evaluation: evaluationReport,
        onDismiss: onDismissEvaluationReport,
      ),
    );
  }

  // P1-3：仅 suggestion 类型 assistant 消息显示采纳按钮。
  // 收敛：采纳动作统一由调用方接 suggestion_adoption_service，
  // 本处只负责渲染入口，不直接操作章节数据。
  if (!isStreamingBubble &&
      msg.role == 'assistant' &&
      msg.messageType == 'suggestion' &&
      onAdoptSuggestion != null) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MessageBubble(message: msg),
        Padding(
          padding: const EdgeInsets.only(left: 40, bottom: 8),
          child: TextButton(
            onPressed: onAdoptSuggestion,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '采纳',
              style: TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  return null;
}
