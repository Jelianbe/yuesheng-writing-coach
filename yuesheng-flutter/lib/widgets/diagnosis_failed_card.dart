// ─────────────────────────────────────────────────────────────
// DiagnosisFailedCard — 诊断失败卡片（缺口清单 B 类：消息卡片类型）
// 真源：yuesheng-android/src/components/chat/message-cards/DiagnosisFailedCard.tsx
//
// 展示型卡片：诊断未检出明显问题时触发——
//   1. 搜索图标圆底 + 「未检测到明显问题」
//   2. 建议列表（默认 3 条 / 可外部注入）
//   3. 双按钮：补充内容 / 继续对话
//   4. failureCount ≥ 阈值时显示多次失败提示
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/shared_constants.dart';
import '../services/message_card_service.dart';

/// 默认诊断失败建议列表（对齐 RN DEFAULT_DIAGNOSIS_SUGGESTIONS）
const List<String> defaultDiagnosisSuggestions = [
  '上传一段你最近写的文章',
  '描述你写作时卡住的场景',
  '具体说说遇到的问题',
];

class DiagnosisFailedCard extends StatelessWidget {
  final int failureCount;

  /// 建议列表，不传则使用默认建议
  final List<String> suggestions;

  /// 补充内容回调（对齐 RN onAddContent）
  final VoidCallback? onAddContent;

  /// 继续对话回调（对齐 RN onContinueChat）
  final VoidCallback? onContinueChat;

  const DiagnosisFailedCard({
    super.key,
    required this.failureCount,
    this.suggestions = const [],
    this.onAddContent,
    this.onContinueChat,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  /// 由 MessageList message_type='diagnosis_failed' 分支直接调用
  static DiagnosisFailedCard fromMessageContent(
    String content, {
    Key? key,
    VoidCallback? onAddContent,
    VoidCallback? onContinueChat,
  }) {
    try {
      final payload = DiagnosisFailedCardPayload.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      return DiagnosisFailedCard(
        key: key,
        failureCount: payload.failureCount,
        onAddContent: onAddContent,
        onContinueChat: onContinueChat,
      );
    } catch (_) {
      return DiagnosisFailedCard(
        key: key,
        failureCount: 0,
        onAddContent: onAddContent,
        onContinueChat: onContinueChat,
      );
    }
  }

  /// 展示建议：外部注入优先，否则默认建议
  List<String> get _displaySuggestions =>
      suggestions.isNotEmpty ? suggestions : defaultDiagnosisSuggestions;

  @override
  Widget build(BuildContext context) {
    final showHint = failureCount >= UILimits.failureWarningThreshold;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xsm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              // 搜索图标圆底（对齐 RN iconContainer bgTint）
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search,
                  size: 28,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '未检测到明显问题',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '你可以尝试补充更多写作内容或具体描述遇到的问题。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 12),
              _buildSuggestions(),
              const SizedBox(height: 12),
              _buildButtonRow(),
              if (showHint) ...[
                const SizedBox(height: 8),
                const Text(
                  '提示：多次诊断失败后建议主动描述问题',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.disabledText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 建议列表（对齐 RN suggestionsSection）
  Widget _buildSuggestions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '建议：',
            style: AppTextStyles.subBody.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final suggestion in _displaySuggestions)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xsm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: AppTextStyles.subBody.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 按钮行：补充内容（primary）| 继续对话（描边）
  Widget _buildButtonRow() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: FilledButton(
              onPressed: onAddContent ?? () {},
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('补充内容'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 38,
            child: OutlinedButton(
              onPressed: onContinueChat ?? () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textTertiary,
                side: const BorderSide(color: AppColors.border),
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('继续对话'),
            ),
          ),
        ),
      ],
    );
  }
}
