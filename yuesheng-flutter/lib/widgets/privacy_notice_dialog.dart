// ─────────────────────────────────────────────────────────────
// privacy_notice_dialog — 隐私与费用告知（v0.1 首次分发）
//
// 双落点（发布准备批任务 2）：
//   1. 首启一次性：问卷完成/跳过后弹出（maybeShowPrivacyNoticeOnce，
//      flag 存 app_state KV，key = privacy_notice_acknowledged）；
//   2. 设置页常驻入口：主动查看，复用同一对话框。
// 文案为拟稿，发布前需舰长过目（台账登记）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/repositories/app_state_repository.dart';

/// app_state KV key：隐私告知是否已确认（'1' = 已确认）
const String kPrivacyNoticeAckKey = 'privacy_notice_acknowledged';

/// 首启一次性告知：未确认过则弹对话框，用户确认后落 flag。
///
/// flag 未落（如确认前杀进程）时下次仍会尝试，设置页入口为兜底。
Future<void> maybeShowPrivacyNoticeOnce(
  BuildContext context,
  AppStateRepository appState,
) async {
  final acked = await appState.getValue(kPrivacyNoticeAckKey);
  if (acked == '1') return;
  if (!context.mounted) return;
  await showPrivacyNoticeDialog(context);
  await appState.setValue(kPrivacyNoticeAckKey, '1');
}

/// 隐私与费用告知对话框（不可点外部关闭，须按「我知道了」）
Future<void> showPrivacyNoticeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('开始之前，请了解', style: AppTextStyles.titleLg),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '· 你的作品文本会发送至 DeepSeek API，用于生成诊断与教学反馈。',
            style: AppTextStyles.body,
          ),
          SizedBox(height: 8),
          Text('· 全部数据仅存储在你的设备本地，本应用无任何遥测与数据上报。', style: AppTextStyles.body),
          SizedBox(height: 8),
          Text(
            '· API 费用由你自己的 DeepSeek 账户按用量承担，本应用不代收任何费用。',
            style: AppTextStyles.body,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
          ),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );
}
