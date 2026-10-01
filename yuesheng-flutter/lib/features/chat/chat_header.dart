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

import '../../config/app_theme.dart';
import '../../config/reasoning_tier.dart';
import '../../widgets/yue_sheet.dart';
import '../../types/teaching_types.dart';
import '../../config/app_palette.dart';

// 顶栏高度（对齐 Material toolbar 默认 56，SafeArea(top) 内）
const double _kChatHeaderHeight = 56;
// 单个 IconButton 触控宽近似（标题居中限宽用）
const double _kBtnZoneWidth = 52;

/// 未接线时的思考档位回调占位：菜单入口**不随接线状态忽隐忽现**。
void _ignoreTierChange(String _) {}

/// 未接线时的教练设置回调占位（P0-4c：菜单入口不随接线忽隐忽现）。
void _ignoreCoachSettings() {}

/// 未接线时的微任务入口回调占位（ADR-C121：入口不随接线忽隐忽现）。
void _ignoreMicroTask() {}

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

  /// 当前激活的教练人格名（用户自定义 → 显示名；系统预设 / 无 → null）。
  /// 非空时菜单「态度档位」区改显「当前教练」，消除「自定义了却显示豆包」的错觉。
  final String? activePersonaName;

  /// 点主引用小字 → 打开引用管理（设主/添加/移除主引用）
  final VoidCallback? onTapPrimaryRef;

  /// 当前思考档位 key（真源 `config/reasoning_tier.dart`）
  final String reasoningTier;

  /// 切换思考档位（与设置页「模型行为」共用同一 provider）
  final ValueChanged<String> onReasoningTierChange;

  /// 打开教练设置（P0-4c 方案 B：对话内快速切换保留，另供完整管理直达）
  final VoidCallback onOpenCoachSettings;

  /// 打开小白冷启动微任务卡片墙（ADR-C121：常驻可达，不依赖空态欢迎）
  final VoidCallback onOpenMicroTask;

  const ChatHeader({
    super.key,
    required this.currentAttitude,
    required this.onAttitudeChange,
    required this.onOpenSessionDrawer,
    required this.onOpenProfile,
    required this.onNewSession,
    this.entryPoint,
    this.primaryRefTitle,
    this.activePersonaName,
    this.onTapPrimaryRef,
    this.reasoningTier = reasoningTierStandard,
    this.onReasoningTierChange = _ignoreTierChange,
    this.onOpenCoachSettings = _ignoreCoachSettings,
    this.onOpenMicroTask = _ignoreMicroTask,
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
              _buildAttitudeSection(context, sheetCtx),
              _buildTierSection(context, sheetCtx),
              _buildProfileEntry(context, sheetCtx),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttitudeSection(BuildContext context, BuildContext sheetCtx) {
    final activeName = activePersonaName;
    return _menuSection(
      context,
      label: activeName != null ? '当前教练' : '态度档位',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (activeName != null)
            _buildCurrentCoach(context, sheetCtx, activeName)
          else
            _buildSystemAttitudeChips(context, sheetCtx),
          const SizedBox(height: AppSpacing.sm),
          _buildManageCoachEntry(context, sheetCtx),
        ],
      ),
    );
  }

  /// P0-4c（方案 B）：对话内快速切换保留，另供「管理教练 ›」直达设置页完整管理。
  Widget _buildManageCoachEntry(BuildContext context, BuildContext sheetCtx) {
    final palette = context.palette;
    return InkWell(
      onTap: () {
        Navigator.pop(sheetCtx);
        onOpenCoachSettings();
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.tune, size: 16, color: palette.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '管理教练',
              style: TextStyle(fontSize: 14, color: palette.textSecondary),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, size: 18, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }

  /// 激活自定义人格时：显示当前人格名 + 系统档位 chips（点可切回系统预设）。
  Widget _buildCurrentCoach(
    BuildContext context,
    BuildContext sheetCtx,
    String name,
  ) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.person_outline, size: 16, color: palette.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: palette.primarySoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '自定义',
                style: TextStyle(fontSize: 11, color: palette.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '点下方档位可切回系统预设',
          style: TextStyle(fontSize: 12, color: palette.textTertiary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildSystemAttitudeChips(context, sheetCtx),
      ],
    );
  }

  /// 三个系统态度档位 chips（豆包/月笙如歌/sensei 快速切换）。
  Widget _buildSystemAttitudeChips(
    BuildContext context,
    BuildContext sheetCtx,
  ) {
    return Row(
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
    );
  }

  Widget _buildTierSection(BuildContext context, BuildContext sheetCtx) {
    return _menuSection(
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
            style: TextStyle(fontSize: 12, color: context.palette.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileEntry(BuildContext context, BuildContext sheetCtx) {
    return InkWell(
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
        height: _kChatHeaderHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.palette.background,
          border: Border(bottom: BorderSide(color: context.palette.borderSoft)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 左右按钮区各自贴边，不参与 Spacer 分配 ⇒ 标题恒居中；
            // 居中主体限宽 = 总宽 − 两侧按钮区 ⇒ 主引用长文本触发省略号、
            // 永不过流、绝不把右侧「写第一句/新建对话/更多」挤掉。
            // ADR-C121：右侧新增「写第一句」⇒ 按钮区 1 左 + 3 右 = 4 区。
            const btnZone = _kBtnZoneWidth; // 单个 IconButton 触控宽近似
            final titleMaxW = (constraints.maxWidth - btnZone * 4).clamp(
              0.0,
              double.infinity,
            );
            return Stack(
              alignment: Alignment.center,
              children: [
                _buildCenterSubject(context, titleMaxW),
                _buildLeadingButton(context),
                _buildTrailingButtons(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCenterSubject(BuildContext context, double titleMaxW) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: titleMaxW),
      child: _isManuscriptEntry
          ? _buildDiagnosisBadgeRow(context)
          : _buildPrimaryRefRow(context),
    );
  }

  Widget _buildDiagnosisBadgeRow(BuildContext context) {
    return Row(
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
        _buildDiagnosisBadge(context),
      ],
    );
  }

  Widget _buildDiagnosisBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: context.palette.l2,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.palette.l2Text),
      ),
      child: Text(
        '诊断模式',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: context.palette.l2Text,
        ),
      ),
    );
  }

  Widget _buildPrimaryRefRow(BuildContext context) {
    return Column(
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
        _buildPrimaryRefText(context),
      ],
    );
  }

  Widget _buildPrimaryRefText(BuildContext context) {
    final label = primaryRefTitle != null && primaryRefTitle!.isNotEmpty
        ? primaryRefTitle!
        : '未关联书籍 · 点此管理';
    return GestureDetector(
      onTap: onTapPrimaryRef,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: context.palette.textTertiary,
        ),
      ),
    );
  }

  Widget _buildLeadingButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        icon: Icon(Icons.menu, color: context.palette.textPrimary),
        tooltip: '会话列表',
        onPressed: onOpenSessionDrawer,
      ),
    );
  }

  Widget _buildTrailingButtons(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ADR-C121：头部常驻「写第一句」微任务入口（30 秒微任务→立刻诊断）
          IconButton(
            icon: Icon(Icons.edit_note, color: context.palette.textPrimary),
            tooltip: '写第一句',
            onPressed: onOpenMicroTask,
          ),
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
            icon: Icon(Icons.more_horiz, color: context.palette.textPrimary),
            tooltip: '更多',
            onPressed: () => _showMoreMenu(context),
          ),
        ],
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
          vertical: AppSpacing.xs,
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
          vertical: AppSpacing.xs,
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
