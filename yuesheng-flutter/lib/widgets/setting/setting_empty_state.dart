// ─────────────────────────────────────────────────────────────
// SettingEmptyState — 「资料」Tab 四子列表的**统一空态**
//
// 背景（2026-09-20 观感改造批）：四个子列表的空态此前**各写各的**，
// 形态参差到了同一容器里能看出两种范式：
//   · 角色 / 大纲 —— 光秃秃一行 14px 小字，无插图无按钮（`Center(Text)`）；
//   · 世界观 / 其他 —— 标题 + 说明 + 主 CTA 按钮（形态正确）。
// 同一屏上下切换时观感断裂，是「太丑」的直接来源之一。
//
// 本组件把**世界观那套已经定型的形态**抽成公共件，四子列表共用：
//     图标（弱化容器） → 标题 → 说明 → 主 CTA（可选）
//
// ★ 为什么主 CTA 是**可选**的：不是每个子列表都有「手动新建」这个动作。
//   大纲实体由 AI 沉淀（`outline_entity_list_view.dart`），无手动新建入口
//   —— 若强行塞一个按钮，就得**编造**一个不存在的动作。无 CTA 时本组件
//   只渲染「图标 + 标题 + 说明」，版式仍与有 CTA 的一致（垂直居中 + 同宽
//   文字块），不会退化成一行小字。
//
// ★ 为什么图标用 `CircleAvatar` 而非自绘：项目内已有同形用法（首字封面），
//   复用主题色令牌即可，不引入新的视觉语言，也不新增资产文件。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

/// 资料库各子列表的通用空态。
///
/// 版式：垂直居中；图标 → 标题（`titleLg`）→ 说明（`body`）→ 主 CTA。
/// 说明文字最多三行宽度（`maxWidth`），避免长句在窄屏拉成一条细线。
class SettingEmptyState extends StatelessWidget {
  /// 图标（必填）—— 四子列表各选一个语义相符的 Material 图标
  final IconData icon;

  /// 空态标题（必填）—— 一句话说清「这里将出现什么」
  final String title;

  /// 补充说明（必填）—— 一句话说清「怎么让它出现」
  final String description;

  /// 主 CTA 文案；为 null 表示该子列表**没有**可给的动作 ⇒ 不渲染按钮
  final String? actionLabel;

  /// 主 CTA 回调；与 [actionLabel] 同时给出才渲染按钮
  final VoidCallback? onAction;

  /// CTA 是否为描边样式（`false` = 实心，用于「这是唯一入口」的场景）
  final bool tonalAction;

  const SettingEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
    this.tonalAction = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        // 键盘弹出 / 小屏横置时，空态整体可滚，避免底部 CTA 被挤出屏外
        // （`Center` 内直接放 Column 会 overflow 报红）。
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.section,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: AppTextStyles.titleLg,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              ?_buildAction(),
            ],
          ),
        ),
      ),
    );
  }

  /// 弱化圆形底板 + 主题色图标（R-019：由 [build] 抽出）。
  Widget _buildIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 26, color: AppColors.primary),
    );
  }

  /// 主 CTA；未给动作时返回 null（由 `?` 展开语法**整块省略**，
  /// 不留空白占位）。R-019：由 [build] 抽出。
  Widget? _buildAction() {
    final label = actionLabel;
    final callback = onAction;
    if (label == null || callback == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: tonalAction
          ? FilledButton.tonal(onPressed: callback, child: Text(label))
          : FilledButton(onPressed: callback, child: Text(label)),
    );
  }
}

/// 搜索 / 筛选**无结果**时的空态（与「首见空态」区分开）。
///
/// ★ 两者必须分开（2026-09-20 改造的实证教训）：`world_fact_list_view.dart`
///   原先把「列表为空」与「搜索无命中」混在同一个判据里，`_filtered()`
///   合并了归档行之后 ⇒ 用户**没输搜索词**也可能落到「没有匹配『』」
///   分支（引号里还是空的），显示一条自相矛盾的提示。
///   本组件不带 CTA —— 用户此刻要的是「清掉筛选」，不是「新建东西」，
///   给新建按钮反而会诱导出重复数据。
class SettingSearchEmptyState extends StatelessWidget {
  /// 无命中时展示的检索词（会加引号）
  final String query;

  /// 「清除筛选」回调；为 null 时不渲染该按钮
  final VoidCallback? onClear;

  /// 该列表在检索范围上被**默认排除**了哪些行（如世界观的归档行）。
  /// 非空时会追加一句说明 —— 否则用户会以为「搜不到 = 不存在」。
  final String? excludedHint;

  const SettingSearchEmptyState({
    super.key,
    required this.query,
    this.onClear,
    this.excludedHint,
  });

  @override
  Widget build(BuildContext context) {
    final clear = onClear;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_outlined,
              size: 32,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '没有匹配「$query」的结果',
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            if (excludedHint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                excludedHint!,
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
            ],
            if (clear != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: clear, child: const Text('清除筛选')),
            ],
          ],
        ),
      ),
    );
  }
}
