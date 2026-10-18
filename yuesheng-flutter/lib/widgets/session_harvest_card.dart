// ─────────────────────────────────────────────────────────────
// SessionHarvestCard — 会话收口卡「本次收获」（T-20261018-02 · A 议题）
//
// 裁定链：T-20261016-06 配重诊断 → 舰长 2026-10-18「A+C 立项并排期为
// 当前主线」→ 设计批（R-027 文案七条）舰长批「批」。
//
// 定位：诊断完成后的**会话级事实小结**——学员学完一轮能看到
// 「本轮发生了什么」（症候计数 / 与上次对比 / 训练 / 成稿快照 / 下一焦点）。
//
// ★ R-009 红线（设计批 §二，机器锚见 session_harvest_test）：
//   全卡只陈述事实（计数/对比/快照），**无「进步了/变好了/达成」类评价词**。
//   措辞形态对齐 EvaluationReportPanel E-1 复诊行先例（只报计数）。
//   成稿节只报 goal/wordCount 数字，无「达标/通过」语（M4 聚合器头注同源）。
//
// 各节条件渲染：payload 某 section 为 null ⇒ 该节不渲染（不造空区）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../config/app_theme.dart';
import '../services/message_card_service.dart';
import '../theme/app_typography.dart';

class SessionHarvestCard extends StatelessWidget {
  final SessionHarvestPayload payload;

  const SessionHarvestCard({super.key, required this.payload});

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  /// （由 message_card_dispatcher 的 'session_harvest' 分支调用；
  /// 解析失败返回 null —— 调用方不渲染，不造坏卡）。
  static SessionHarvestCard? tryFromMessageContent(String content, {Key? key}) {
    try {
      final payload = SessionHarvestPayload.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      return SessionHarvestCard(key: key, payload: payload);
    } catch (_) {
      return null;
    }
  }

  /// R-027 批文文案锚（§四 清单七条；改串须重走 R-027）。
  static const String kTitleText = '本次收获';
  static const String kCountSuffix = '次诊断';
  static const String kDiagnosisLinePrefix = '本章报出';
  static const String kDiffPrefix = '与上次诊断相比：';
  static const String kDiffAdded = '新增';
  static const String kDiffRemoved = '消失';
  static const String kDiffRecurring = '复现';
  static const String kTrainingPrefix = '训练';
  static const String kTrainingTimes = '次 · 通过';
  static const String kTrainingTimesSuffix = '次';
  static const String kCompletionPrefix = '本章独立成稿：目标';
  static const String kCompletionMid = '字 · 当前';
  static const String kCompletionSuffix = '字';
  static const String kNextFocusPrefix = '下一次建议关注：';

  int get _totalSyndromes =>
      payload.l1Count + payload.l2Count + payload.l3Count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: context.palette.surfaceWhite,
            border: Border.fromBorderSide(
              BorderSide(color: context.palette.border),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: AppSpacing.sm),
                _buildDiagnosisLine(context),
                if (payload.diff != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _buildDiffLine(context),
                ],
                if (payload.training != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _buildTrainingLine(context),
                ],
                if (payload.completion != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _buildCompletionLine(context),
                ],
                if (payload.nextFocusName != null &&
                    payload.nextFocusName!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _buildNextFocusLine(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 18,
          color: context.palette.primary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '$kTitleText · 第 ${payload.diagnosisCount} $kCountSuffix',
          style: context.text.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildDiagnosisLine(BuildContext context) {
    // 批文 §四.3 格式逐字：「本章报出 X 条 · L1×n L2×n L3×n」
    // （X = 症候总数；各级计数按 severity 汇总，不列明细）
    final levels = <String>[];
    if (payload.l1Count > 0) levels.add('L1×${payload.l1Count}');
    if (payload.l2Count > 0) levels.add('L2×${payload.l2Count}');
    if (payload.l3Count > 0) levels.add('L3×${payload.l3Count}');
    final detail = levels.isEmpty ? '' : ' · ${levels.join(' ')}';
    return Text(
      '$kDiagnosisLinePrefix $_totalSyndromes 条$detail',
      style: context.text.subBody,
    );
  }

  Widget _buildDiffLine(BuildContext context) {
    final d = payload.diff!;
    return Text(
      '$kDiffPrefix$kDiffAdded ${d.added} · $kDiffRemoved ${d.removed} · '
      '$kDiffRecurring ${d.recurring}',
      style: context.text.subBody,
    );
  }

  Widget _buildTrainingLine(BuildContext context) {
    final t = payload.training!;
    return Text(
      '$kTrainingPrefix ${t.attempts} $kTrainingTimes ${t.passed} $kTrainingTimesSuffix',
      style: context.text.subBody,
    );
  }

  Widget _buildCompletionLine(BuildContext context) {
    final c = payload.completion!;
    return Text(
      '$kCompletionPrefix ${c.goalWords} $kCompletionMid ${c.wordCount} $kCompletionSuffix',
      style: context.text.subBody,
    );
  }

  Widget _buildNextFocusLine(BuildContext context) {
    return Text(
      '$kNextFocusPrefix${payload.nextFocusName}',
      style: context.text.subBody,
    );
  }
}
