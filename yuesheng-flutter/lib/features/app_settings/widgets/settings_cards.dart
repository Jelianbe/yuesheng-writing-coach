// ─────────────────────────────────────────────────────────────
// settings_cards — 设置区块的三个通用展示组件（从 settings_page.dart 抽出）
//
// 为什么抽出（而不是把 `_` 去掉直接共用）：
//   「填表单 + 测试 + 保存」整块已下沉为独立子页
//   （`api_config_page.dart`，路由 `/settings/api-config`），
//   于是 `_SectionCard` / `_FieldLabel` / `_ActionRow` 同时被
//   settings_page 与 api_config_page 两个文件消费。私有符号跨文件不可见，
//   只能二选一：把去 `_` 暴露成 settings_page 的公开 API（污染页面文件
//   的公开面），或抽到 features 内的共享文件（依赖方向更干净）。
//   选后者 —— 与 v0.3 的 features-based 分层一致：
//   页面文件只放页面，跨页复用的展示原子放 widgets/。
//
// ★ 组件**形状与迁移前逐字一致**（含 doc注释），仅可见性由 private 变 public。
//   任何"顺手优化"都会让 settings_page 的既有用例失去对照基线。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../config/app_palette.dart';
import '../../../config/app_theme.dart';
import '../../../theme/app_typography.dart';

/// 「尚未配置 API」警告条的**前半句**（两页逐字相同）。
///
/// 为什么提为常量（2026-10-04）：这句原来在 settings_page 与 api_config_page
/// 各写一份字面量，改一边另一边就漂——两页在屏上会被用户连着看，措辞不一致
/// 显得像两套人写的。**前缀必须一字不差**，故锁在共享文件里。
const String kUnconfiguredWarningPrefix = '尚未配置 API，当前为免费测试模式（离线示例）。';

/// 警告条的完整文案 = 前缀 + 行动指引。
///
/// 指引随页面位置而异（这是**有意**不同，不是漂移）：
///   · [onSettingsPage] = true：设置页本身没有表单，表单在别的页 ⇒「点击下方…」
///   · [onSettingsPage] = false：表单就在本页正下方 ⇒「填写下方表单…」
String buildUnconfiguredWarning({required bool onSettingsPage}) =>
    '$kUnconfiguredWarningPrefix'
    '${onSettingsPage ? '点击下方「添加 / 编辑 API 配置」以启用完整功能' : '填写下方表单以启用完整功能'}';

/// 区块卡片（对齐 RN section：bgCard + 圆角 + 边框）
class SectionCard extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;

  const SectionCard({
    super.key,
    required this.title,
    this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 表单字段标签（API Key / Base URL / Model / 账号列表标题共用）
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(
        text,
        style: context.text.subBody.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 可点击的入口行（左侧标题 + 右箭头）
class ActionRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const ActionRow({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.palette.disabledText,
            ),
          ],
        ),
      ),
    );
  }
}
