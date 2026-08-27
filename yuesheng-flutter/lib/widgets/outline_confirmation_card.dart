// ─────────────────────────────────────────────────────────────
// OutlineConfirmationCard — 大纲记忆确认卡片（批次73）
//
// 大纲层可交互入口：AI 自主提取的 pending 印象需用户确认后才 active。
// 一个实体一张卡（用户确认粒度），实体下每条印象一行操作：
//   - 「接受」→ approveImpression（印象 active + 实体 active；
//     冲突印象接受 → 旧印象 superseded 二选一）
//   - 「拒绝」→ rejectImpression（印象 rejected；冲突时拒绝即保留旧认知）
//
// 视觉规范（月色竹青）：仿 TeacherSuggestionCard
//   - 卡片 #F7F8F6 + 圆角 12 + 左 4dp 竹青色条
//   - 实体类型 chip：竹青淡 #E8F0EE + 深墨竹青字 #2D5A52
//   - 主按钮「接受」：竹青底 #2D5A52 + 白字；次按钮「拒绝」描边 + 深灰字
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/outline_repository.dart';
import '../providers/app_providers.dart';
import '../services/message_card_service.dart';

/// 实体类型中文映射
const Map<String, String> _entityTypeText = {
  'character': '人物',
  'setting': '设定',
  'plot': '情节',
};

class OutlineConfirmationCard extends ConsumerStatefulWidget {
  final OutlineConfirmationPayload payload;
  final OutlineRepository? repoOverride; // 测试注入

  const OutlineConfirmationCard({
    super.key,
    required this.payload,
    this.repoOverride,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  static OutlineConfirmationCard fromMessageContent(
    String content, {
    Key? key,
    OutlineRepository? repoOverride,
  }) {
    try {
      return OutlineConfirmationCard(
        key: key,
        payload: OutlineConfirmationPayload.fromJson(
          jsonDecode(content) as Map<String, dynamic>,
        ),
        repoOverride: repoOverride,
      );
    } catch (_) {
      // 兜底：空确认卡（正常不会触发）
      return const OutlineConfirmationCard(
        payload: OutlineConfirmationPayload(
          confirmationId: '',
          entityId: '',
          entityType: 'character',
          entityKey: '',
          isNewEntity: false,
          impressions: [],
        ),
      );
    }
  }

  @override
  ConsumerState<OutlineConfirmationCard> createState() =>
      _OutlineConfirmationCardState();
}

class _OutlineConfirmationCardState
    extends ConsumerState<OutlineConfirmationCard> {
  /// 已处理（接受/拒绝）的印象 id
  final Set<String> _processed = {};

  /// 批次5（5.2）：印象 id → DB 当前 status。
  /// 非 pending（expired/active/rejected/superseded）→ 该行置灰，按钮禁用，
  /// 防确认卡永居：卡片是历史快照，重开会话后需以 DB 实际状态为准。
  final Map<String, String> _dbStatuses = {};

  OutlineRepository _repo() {
    return widget.repoOverride ??
        OutlineRepository(ref.read(appDatabaseProvider));
  }

  @override
  void initState() {
    super.initState();
    _loadDbStatuses();
  }

  /// 异步加载印象当前状态（防御：无 DB provider 的纯展示场景静默保持 pending）
  Future<void> _loadDbStatuses() async {
    try {
      final repo = widget.repoOverride != null
          ? widget.repoOverride!
          : OutlineRepository(ref.read(appDatabaseProvider));
      final statuses = <String, String>{};
      for (final im in widget.payload.impressions) {
        final row = await repo.getImpressionById(im.id);
        if (row != null) statuses[im.id] = row.status;
      }
      if (!mounted) return;
      setState(() {
        _dbStatuses.addAll(statuses);
      });
    } catch (_) {
      // 防御：查询失败不阻塞渲染（保持 pending 展示）
    }
  }

  Future<void> _handleApprove(String impressionId) async {
    try {
      await _repo().approveImpression(impressionId);
    } catch (_) {
      // 落库失败仍本地收起（卡片消息仍在，可重现）
    }
    if (mounted) setState(() => _processed.add(impressionId));
  }

  Future<void> _handleReject(String impressionId) async {
    try {
      await _repo().rejectImpression(impressionId);
    } catch (_) {
      // 落库失败仍本地收起
    }
    if (mounted) setState(() => _processed.add(impressionId));
  }

  /// 批次5（5.2）：印象是否已过期/已处理（以 DB 实际状态为准）
  bool _isStale(String impressionId) {
    final status = _dbStatuses[impressionId];
    return status != null && status != 'pending';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final pending = p.impressions.where((i) => !_processed.contains(i.id));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xsm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左 4dp 竹青色条
                Container(width: 4, color: AppColors.primary),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 8),
                        if (pending.isEmpty)
                          _buildAllDone(context)
                        else
                          ...pending.map(
                            (im) => _buildImpressionRow(context, im),
                          ),
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

  /// 卡片头部：大纲记忆待确认 + 实体类型 chip + 新/已有标签
  Widget _buildHeader(BuildContext context) {
    final p = widget.payload;
    final typeName = _entityTypeText[p.entityType] ?? p.entityType;
    return Row(
      children: [
        Text(
          '大纲记忆待确认',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            typeName,
            style: const TextStyle(fontSize: 11, color: AppColors.primary),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: p.isNewEntity
                ? AppColors.primarySoft
                : AppColors.border.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            p.isNewEntity ? '新实体' : '已有实体',
            style: TextStyle(
              fontSize: 11,
              color: p.isNewEntity
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            p.entityKey,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ],
    );
  }

  /// 印象行：文本 + 冲突横幅 + 接受/拒绝按钮
  /// 批次5（5.2）：DB 中已非 pending（过期/已处理）→ 置灰 + 按钮禁用
  Widget _buildImpressionRow(
    BuildContext context,
    OutlineImpressionPayload im,
  ) {
    final isConflict = im.conflictWith != null;
    final isStale = _isStale(im.id);
    final baseColor = isStale ? AppColors.disabledText : AppColors.textPrimary;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.smx),
      decoration: BoxDecoration(
        color: isConflict
            ? AppColors.warningBg
            : (isStale ? AppColors.background : AppColors.surface),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isConflict) ...[
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 4),
                Text(
                  '与既有认知矛盾：接受将更新记忆，拒绝保留原有认知',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(
            im.text,
            style: TextStyle(fontSize: 13, height: 1.4, color: baseColor),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (isStale)
                const Expanded(
                  child: Text(
                    '已过期/已处理',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.disabledText,
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: _actionButton(
                    label: '接受',
                    filled: true,
                    onTap: () => _handleApprove(im.id),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    label: '拒绝',
                    filled: false,
                    onTap: () => _handleReject(im.id),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 全部处理后的收尾态
  Widget _buildAllDone(BuildContext context) {
    final approved = widget.payload.impressions
        .where((i) => _processed.contains(i.id))
        .length;
    return Row(
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 14,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Text(
          '已确认 $approved/${widget.payload.impressions.length} 条印象',
          style: AppTextStyles.noteCaption,
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 30,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
              ),
              child: const Text('接受', style: TextStyle(fontSize: 12)),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: AppColors.border),
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('拒绝', style: TextStyle(fontSize: 12)),
            ),
    );
  }
}
