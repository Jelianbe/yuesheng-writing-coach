// ─────────────────────────────────────────────────────────────
// ChatHeader — 聊天头部状态区（缺口清单第 5 项）
// 真源：yuesheng-android/src/components/chat/ChatHeader.tsx
//
// 结构（对齐 RN）：
//   头部栏（56 高）：
//   - 左：会话列表按钮（汉堡）→ 打开 SessionDrawer
//   - 中：标题「会话」+ 满幅区分（诊断模式徽章 / 主引用书名小字）
//   - 右：更多按钮 → 更多菜单（底部弹层）
//
//   更多菜单（对齐 RN Modal menuSheet）：
//   - 态度档位：行内 3 档选择（对齐 RN AttitudeIndicator 行内语义，
//     避免 bottom sheet 内嵌套弹层）
//   - 思考档位（批次 TH 三）：行内 4 档选择，真源 config/reasoning_tier.dart
//   - 画像：入口 → onOpenProfile
//
// 批次 C78-3c 删除「子阶段」菜单段：SubphaseIndicator 组件已废弃
// （展示层「诊断中/练习中/反馈中」胶囊与教学链路真实状态脱节，
//  保留会造成「显示的子阶段」与 teaching_state.current_subphase 双真源）。
// 教学子阶段语义仍在 chat_service / message_injector 中活跃，未删除。
//
// 批次 C78-3c-2 删除「引用管理」菜单段：与标题下方主引用小字是同一入口
// （chat_page.dart 的 onOpenReferences / onTapPrimaryRef 两回调同指
//  _handleOpenReferences），菜单项属重复入口，去掉后小字仍完整可达。
//
// 差异说明：RN 头部左为返回（Stack 导航），Flutter ChatPage 为 Tab2
// 常驻页无上级返回，左按钮改为会话列表（drawer）入口。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/reasoning_tier.dart';
import 'yue_sheet.dart';
import '../types/teaching_types.dart';
import '../config/app_palette.dart';

/// 未接线时的思考档位回调占位：菜单入口**不随接线状态忽隐忽现**。
void _ignoreTierChange(String _) {}

/// 态度档位行内配置（对齐 RN attitude-rhythm 语义）
/// P1-6：const List 装不进运行期 palette ⇒ 改 **palette 驱动函数**，随主题翻。
List<(AttitudeLevel, String, Color)> _attitudeOptionsFor(AppPalette p) => [
  (AttitudeLevel.doubao, '豆包', p.l1Text),
  (AttitudeLevel.yuesheng, '月笙如歌', p.l2Text),
  (AttitudeLevel.sensei, 'sensei', p.l3Text),
];

class ChatHeader extends StatelessWidget {
  /// 当前态度档位
  final AttitudeLevel currentAttitude;

  /// 态度切换回调
  final ValueChanged<AttitudeLevel> onAttitudeChange;

  /// 打开会话抽屉（对齐 RN onOpenSessionDrawer）
  final VoidCallback onOpenSessionDrawer;

  /// 打开画像（对齐 RN onOpenProfile → StudentProfilePanel）
  final VoidCallback onOpenProfile;

  /// 新建对话（批次 29：头部 ⋯ 左侧快捷入口）
  final VoidCallback onNewSession;

  /// 入口标识：'manuscript' → 「诊断模式」徽章，其他 → 主引用书名小字
  final String? entryPoint;

  /// 当前会话主引用书名（references 里 isPrimary==1 的 title）。
  /// 非 manuscript 入口时显示在标题下方小字；null 表示未关联书籍。
  final String? primaryRefTitle;

  /// 点主引用小字 → 打开引用管理（设主/添加/移除主引用）
  final VoidCallback? onTapPrimaryRef;

  /// 当前思考档位 key（真源 `config/reasoning_tier.dart`）
  final String reasoningTier;

  /// 切换思考档位（与设置页「模型行为」共用同一 provider）
  final ValueChanged<String> onReasoningTierChange;

  const ChatHeader({
    super.key,
    required this.currentAttitude,
    required this.onAttitudeChange,
    required this.onOpenSessionDrawer,
    required this.onOpenProfile,
    required this.onNewSession,
    this.entryPoint,
    this.primaryRefTitle,
    this.onTapPrimaryRef,
    this.reasoningTier = reasoningTierStandard,
    this.onReasoningTierChange = _ignoreTierChange,
  });

  bool get _isManuscriptEntry => entryPoint == 'manuscript';

  void _showMoreMenu(BuildContext context) {
    showYueModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.background,
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _menuSection(
                context,
                label: '态度档位',
                child: Row(
                  children: [
                    for (final (attitude, label, color) in _attitudeOptionsFor(
                      context.palette,
                    )) ...[
                      _AttitudeChip(
                        label: label,
                        color: color,
                        active: attitude == currentAttitude,
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          onAttitudeChange(attitude);
                        },
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
              // 思考档位（批次 TH 三）：与设置页「模型行为」同源同值，
              // 输入框上方开关是二值快捷入口，此处是完整四档
              _menuSection(
                context,
                label: '思考档位',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final preset in reasoningTierPresets)
                          _TierChip(
                            label: preset.label,
                            active: preset.key == reasoningTier,
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              onReasoningTierChange(preset.key);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      reasoningTierOf(reasoningTier).hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // 画像入口（对齐 RN menuAction）
              InkWell(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onOpenProfile();
                },
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 22,
                        color: context.palette.textPrimary,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Text(
                        '画像',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: context.palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuSection(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.palette.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.palette.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea(top)：ChatPage 无 AppBar，body 直顶到屏幕顶端；
    // 不加则整行渲染到状态栏下（模拟器实证：顶部按钮被状态栏遮挡不可点）
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.palette.background,
          border: Border(bottom: BorderSide(color: context.palette.borderSoft)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 左右按钮区各自贴边，不参与 Spacer 分配 ⇒ 标题恒居中；
            // 居中主体限宽 = 总宽 − 两侧按钮区 ⇒ 主引用长文本触发省略号、
            // 永不过流、绝不把右侧「新建对话/更多」挤掉。
            const btnZone = 52.0; // 单个 IconButton 触控宽近似
            final titleMaxW = (constraints.maxWidth - btnZone * 3).clamp(
              0.0,
              double.infinity,
            );
            return Stack(
              alignment: Alignment.center,
              children: [
                // ① 居中主体（诊断模式徽章 / 会话 + 主引用小字），限宽
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: titleMaxW),
                  child: _isManuscriptEntry
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '会话',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.palette.textPrimary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: context.palette.l2,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                border: Border.all(
                                  color: context.palette.l2Text,
                                ),
                              ),
                              child: Text(
                                '诊断模式',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: context.palette.l2Text,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '会话',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.palette.textPrimary,
                              ),
                            ),
                            GestureDetector(
                              onTap: onTapPrimaryRef,
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                primaryRefTitle != null &&
                                        primaryRefTitle!.isNotEmpty
                                    ? primaryRefTitle!
                                    : '未关联书籍 · 点此管理',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: context.palette.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                // ② 左：会话列表按钮（贴左，对齐 RN sessionList 按钮）
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(Icons.menu, color: context.palette.textPrimary),
                    tooltip: '会话列表',
                    onPressed: onOpenSessionDrawer,
                  ),
                ),
                // ③ 右：新建对话 + 更多（贴右）
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 批次 29：新建对话快捷入口（⋯ 左侧，避免进抽屉才能新建）
                      IconButton(
                        icon: Icon(
                          Icons.add_comment_outlined,
                          color: context.palette.textPrimary,
                        ),
                        tooltip: '新建对话',
                        onPressed: onNewSession,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.more_horiz,
                          color: context.palette.textPrimary,
                        ),
                        tooltip: '更多',
                        onPressed: () => _showMoreMenu(context),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 更多菜单中的行内态度档位选择
class _AttitudeChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _AttitudeChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xsm,
        ),
        decoration: BoxDecoration(
          color: active ? context.palette.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: active
              ? Border.all(color: color)
              : Border.all(color: context.palette.borderSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 更多菜单中的行内思考档位选择（与 _AttitudeChip 的区别：无颜色编码，
/// 档位不是「风格」而是「强度」，用主色描边表示选中即可）
class _TierChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TierChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xsm,
        ),
        decoration: BoxDecoration(
          color: active ? context.palette.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: active
                ? context.palette.primary
                : context.palette.borderSoft,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active
                ? context.palette.primary
                : context.palette.textPrimary,
          ),
        ),
      ),
    );
  }
}
