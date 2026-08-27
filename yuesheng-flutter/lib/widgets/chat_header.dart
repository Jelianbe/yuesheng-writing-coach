// ─────────────────────────────────────────────────────────────
// ChatHeader — 聊天头部状态区（缺口清单第 5 项）
// 真源：yuesheng-android/src/components/chat/ChatHeader.tsx
//
// 结构（对齐 RN）：
//   头部栏（56 高）：
//   - 左：会话列表按钮（汉堡）→ 打开 SessionDrawer
//   - 中：标题「会话」+ 入口徽章（诊断模式 / 自由对话）
//   - 右：更多按钮 → 更多菜单（底部弹层）
//
//   更多菜单（对齐 RN Modal menuSheet）：
//   - 阶段（只读）：PHASE_LABELS[currentPhase]
//   - 子阶段：SubphaseIndicator + 切换按钮（onNextSubphase 循环切换）
//   - 态度档位：行内 3 档选择（对齐 RN AttitudeIndicator 行内语义，
//     避免 bottom sheet 内嵌套弹层）
//   - 画像：入口 → onOpenProfile
//
// 差异说明：RN 头部左为返回（Stack 导航），Flutter ChatPage 为 Tab2
// 常驻页无上级返回，左按钮改为会话列表（drawer）入口。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../types/teaching_types.dart';
import 'subphase_indicator.dart';

/// 阶段标签（对齐 RN PHASE_LABELS）
const Map<String, String> _phaseLabels = {
  'P0_ENGAGE': '建立投入',
  'P1_WORLD': '暴露问题',
  'P2_PRACTICE_LOOP': '训练循环',
  'P3_TRAINING': '深度训练',
  'P4_REVIEW': '复盘阶段',
};

/// 态度档位行内配置（对齐 RN attitude-rhythm 语义）
const List<(AttitudeLevel, String, Color)> _attitudeOptions = [
  (AttitudeLevel.doubao, '豆包', AppColors.l1Text),
  (AttitudeLevel.yuesheng, '月笙如歌', AppColors.l2Text),
  (AttitudeLevel.sensei, 'sensei', AppColors.l3Text),
];

class ChatHeader extends StatelessWidget {
  /// 当前态度档位
  final AttitudeLevel currentAttitude;

  /// 当前教学阶段
  final TeachingPhase currentPhase;

  /// 当前 P2 子阶段（可空）
  final TeachingSubphase? currentSubphase;

  /// 态度切换回调
  final ValueChanged<AttitudeLevel> onAttitudeChange;

  /// 子阶段切换回调（循环 DIAGNOSIS→PRACTICE→FEEDBACK）
  final VoidCallback onNextSubphase;

  /// 打开会话抽屉（对齐 RN onOpenSessionDrawer）
  final VoidCallback onOpenSessionDrawer;

  /// 打开画像（对齐 RN onOpenProfile → StudentProfilePanel）
  final VoidCallback onOpenProfile;

  /// 新建对话（批次 29：头部 ⋯ 左侧快捷入口）
  final VoidCallback onNewSession;

  /// 打开引用管理（对齐 RN onOpenReferences → ReferenceBar 管理弹层）
  final VoidCallback onOpenReferences;

  /// 入口标识：'manuscript' → 诊断模式徽章，其他 → 自由对话
  final String? entryPoint;

  const ChatHeader({
    super.key,
    required this.currentAttitude,
    required this.currentPhase,
    required this.currentSubphase,
    required this.onAttitudeChange,
    required this.onNextSubphase,
    required this.onOpenSessionDrawer,
    required this.onOpenProfile,
    required this.onNewSession,
    required this.onOpenReferences,
    this.entryPoint,
  });

  bool get _isManuscriptEntry => entryPoint == 'manuscript';

  void _showMoreMenu(BuildContext context) {
    showYueModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
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
                label: '当前阶段',
                child: Text(
                  _phaseLabels[currentPhase.value] ?? currentPhase.value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _menuSection(
                label: '子阶段',
                child: Row(
                  children: [
                    SubphaseIndicator(subphase: currentSubphase),
                    const SizedBox(width: AppSpacing.md),
                    InkWell(
                      onTap: onNextSubphase,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.xsm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Text(
                          '切换',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _menuSection(
                label: '态度档位',
                child: Row(
                  children: [
                    for (final (attitude, label, color)
                        in _attitudeOptions) ...[
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
                    children: const [
                      Icon(
                        Icons.person_outline,
                        size: 22,
                        color: AppColors.textPrimary,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Text(
                        '画像',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 引用管理入口（修复「@ 只能添加、不能撤销/设主」的断裂链路）
              InkWell(
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onOpenReferences();
                },
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 22,
                        color: AppColors.textPrimary,
                      ),
                      SizedBox(width: AppSpacing.md),
                      Text(
                        '引用管理',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
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

  Widget _menuSection({required String label, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
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
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
        ),
        child: Row(
          children: [
            // 左：会话列表（汉堡 → drawer，对齐 RN sessionList 按钮）
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.textPrimary),
              tooltip: '会话列表',
              onPressed: onOpenSessionDrawer,
            ),
            const Spacer(),
            // 中：标题 + 入口徽章
            const Text(
              '会话',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: _isManuscriptEntry ? AppColors.l2 : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: _isManuscriptEntry
                      ? AppColors.l2Text
                      : AppColors.borderSoft,
                ),
              ),
              child: Text(
                _isManuscriptEntry ? '诊断模式' : '自由对话',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _isManuscriptEntry
                      ? AppColors.l2Text
                      : AppColors.textTertiary,
                ),
              ),
            ),
            const Spacer(),
            // 批次 29：新建对话快捷入口（⋯ 左侧，避免进抽屉才能新建）
            IconButton(
              icon: const Icon(
                Icons.add_comment_outlined,
                color: AppColors.textPrimary,
              ),
              tooltip: '新建对话',
              onPressed: onNewSession,
            ),
            // 右：更多按钮
            IconButton(
              icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
              tooltip: '更多',
              onPressed: () => _showMoreMenu(context),
            ),
          ],
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
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: active
              ? Border.all(color: color)
              : Border.all(color: AppColors.borderSoft),
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
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
