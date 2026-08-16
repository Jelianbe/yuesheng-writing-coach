// ─────────────────────────────────────────────────────────────
// PartialAgreementCard — 部分认同反馈卡片（缺口清单 B 类：消息卡片类型）
// 真源：yuesheng-android/src/components/chat/message-cards/PartialAgreementCard.tsx
//
// 交互式卡片：学员对诊断结果部分认同时触发——
//   1. 症候名 + severity 徽标（矿物色）
//   2. 多行反馈输入框
//   3. 3 个快速选项（症状描述不准 / 缺少某个问题 / 严重度不对）
//   4. 「跳过此症候」/「提交反馈」双按钮（空输入禁用提交）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/message_card_service.dart';

/// 部分认同快速选项（对齐 RN DEFAULT_QUICK_OPTIONS，导出供外部引用/配置）
const List<({String label, String value})> defaultQuickOptions = [
  (label: '症状描述不准', value: 'symptom_inaccurate'),
  (label: '缺少某个问题', value: 'missing_problem'),
  (label: '严重度不对', value: 'severity_wrong'),
];

/// 快速选项 value → 中文 label（批次81：回调侧构造用户反馈消息文案用；
/// 未命中时原样返回，保证文案不丢）
String quickOptionLabel(String value) {
  for (final option in defaultQuickOptions) {
    if (option.value == value) return option.label;
  }
  return value;
}

/// 严重度 → （文字色, 底/边框色）
({Color text, Color bg}) _severityColors(String severity) {
  switch (severity) {
    case 'L2':
      return (text: AppColors.l2Text, bg: AppColors.l2);
    case 'L3':
      return (text: AppColors.l3Text, bg: AppColors.l3);
    default:
      return (text: AppColors.l1Text, bg: AppColors.l1);
  }
}

class PartialAgreementCard extends StatefulWidget {
  final String syndromeId;
  final String syndromeName;
  final String severity; // 'L1' | 'L2' | 'L3'

  /// 提交反馈回调（feedback + 快速选项 value，对齐 RN onSubmit）
  final void Function(String feedback, String? quickOption)? onSubmit;

  /// 跳过此症候回调（对齐 RN onSkip）
  final VoidCallback? onSkip;

  /// 快速选项列表，不传则使用默认选项
  final List<({String label, String value})> quickOptions;

  const PartialAgreementCard({
    super.key,
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    this.onSubmit,
    this.onSkip,
    this.quickOptions = defaultQuickOptions,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  /// 由 MessageList message_type='partial_agreement' 分支直接调用
  static PartialAgreementCard fromMessageContent(
    String content, {
    Key? key,
    void Function(String feedback, String? quickOption)? onSubmit,
    VoidCallback? onSkip,
  }) {
    try {
      final payload = PartialAgreementCardPayload.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      return PartialAgreementCard(
        key: key,
        syndromeId: payload.syndromeId,
        syndromeName: payload.syndromeName,
        severity: payload.severity,
        onSubmit: onSubmit,
        onSkip: onSkip,
      );
    } catch (_) {
      return PartialAgreementCard(
        key: key,
        syndromeId: '',
        syndromeName: '',
        severity: 'L1',
        onSubmit: onSubmit,
        onSkip: onSkip,
      );
    }
  }

  @override
  State<PartialAgreementCard> createState() => _PartialAgreementCardState();
}

class _PartialAgreementCardState extends State<PartialAgreementCard> {
  final TextEditingController _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  void _handleQuickOption(String value) {
    widget.onSubmit?.call(value, value);
  }

  void _handleSubmit() {
    final text = _feedbackController.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit?.call(text, null);
    // 批次81：仅在有外部回调（反馈已真实送出/落库）时清空输入；
    // 未接线时保留文本，杜绝「点了提交反馈却无声无息清空」的误导。
    if (widget.onSubmit != null) {
      _feedbackController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final severity = _severityColors(widget.severity);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧 4dp severity 色条（对齐 RN borderLeftColor + borderLeftWidth 4）
                Container(width: 4, color: severity.text),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(severity),
                        const SizedBox(height: 10),
                        if (widget.syndromeName.isNotEmpty) ...[
                          _buildSyndromeName(),
                          const SizedBox(height: 10),
                        ],
                        const Text(
                          '告诉我哪些描述不准确，我会调整诊断结果。',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildInput(),
                        const SizedBox(height: 10),
                        _buildQuickOptions(),
                        const SizedBox(height: 12),
                        _buildButtonRow(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 头部：标题 + severity 徽标
  Widget _buildHeader(({Color text, Color bg}) severity) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            '请补充不符合的地方',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: severity.bg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            widget.severity,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: severity.text,
            ),
          ),
        ),
      ],
    );
  }

  /// 症候名 chip（对齐 RN brandSoft 底色）
  Widget _buildSyndromeName() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        widget.syndromeName,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  /// 多行反馈输入框
  Widget _buildInput() {
    return TextField(
      controller: _feedbackController,
      onChanged: (_) => setState(() {}),
      minLines: 3,
      maxLines: 3,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: '例如：我觉得问题不严重',
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.disabledText),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.all(10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }

  /// 快速选项横向 chips
  Widget _buildQuickOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '快速选项：',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final option in widget.quickOptions) ...[
                InkWell(
                  onTap: () => _handleQuickOption(option.value),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderSoft),
                    ),
                    child: Text(
                      option.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 按钮行：跳过此症候（描边）| 提交反馈（primary，空输入禁用）
  Widget _buildButtonRow() {
    final hasText = _feedbackController.text.trim().isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: OutlinedButton(
              onPressed: widget.onSkip ?? () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textTertiary,
                side: const BorderSide(color: AppColors.borderSoft),
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('跳过此症候'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 38,
            child: FilledButton(
              onPressed: hasText ? _handleSubmit : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.disabled,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('提交反馈'),
            ),
          ),
        ),
      ],
    );
  }
}
