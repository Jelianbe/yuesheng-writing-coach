// ─────────────────────────────────────────────────────────────
// ChatWelcome — 欢迎态（缺口清单第 5 项）
// 真源：yuesheng-android/src/components/chat/ChatWelcome.tsx
//
// 结构（对齐 RN）：
//   - 月笙圆形头像（primary 底 + 白「月」字，72px）
//   - 标题「你好，我是月笙」
//   - 副标题「你的专属写作教练，随时帮你诊断和提升写作」
//
// 显示条件（对齐 RN chat.tsx L403）：messages.length === 0 时
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

const String _welcomeTitle = '你好，我是月笙';
const String _welcomeSubtitle = '你的专属写作教练，随时帮你诊断和提升写作';

class ChatWelcome extends StatelessWidget {
  const ChatWelcome({super.key, this.onStartWriting});

  /// 批次62：空态行动引导——「去书架写一写」回调（null 时不显示按钮）
  final VoidCallback? onStartWriting;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 月笙圆形头像（对齐 RN ChatWelcome 真源 + 头注释声明；教学老师形象）
            const CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary,
              child: Text(
                '月',
                style: TextStyle(
                  color: AppColors.onPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // UI-AUDIT：走 AppTextStyles 令牌（titleLg=18/w600，空态主文字）
            const Text(_welcomeTitle, style: AppTextStyles.titleLg),
            const SizedBox(height: AppSpacing.sm),
            // UI-AUDIT：副标题改 body（14/textSecondary，对比度 4.68:1 达标；
            // 原 textTertiary 3.23:1 < 4.5:1，14px 正文不达 WCAG AA）
            const Text(
              _welcomeSubtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            // 批次62：空态行动引导——给用户明确的下一步（写作为先）
            if (onStartWriting != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: onStartWriting,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                child: const Text('去书架写一写'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
