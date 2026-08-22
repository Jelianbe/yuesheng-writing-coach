// ─────────────────────────────────────────────────────────────
// SessionDrawer — 会话管理抽屉（缺口清单第 2 项）
// 真源：yuesheng-android/src/components/chat/SessionDrawer.tsx
//
// 结构（对齐 RN）：
//   - 头部：「对话」标题
//   - 会话列表：月字头像（当前会话品牌色 / 其余灰）+ 标题
//     + 相对时间 + 预览 + 阶段标签（currentPhase → PHASE_LABELS）
//   - 空态：还没有会话 + 发起第一次对话 CTA
//   - 底部：「+ 新建会话」按钮
//
// 数据：SessionWithPhase（session + currentPhase）由父级传入
// （对齐 RN sessions 由 useChatStore 提供，Flutter 侧由 ChatPage 加载）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/repositories/session_repository.dart';
import '../types/teaching_types.dart';
import '../utils/time_format.dart';

class SessionDrawer extends StatelessWidget {
  /// 会话列表（listSessionsWithPhase，按 updated_at 降序）
  final List<SessionWithPhase> sessions;

  /// 当前会话 ID（高亮显示）
  final String? currentSessionId;

  /// 选择会话（drawer 先关闭再回调）
  final ValueChanged<String> onSelect;

  /// 新建会话（drawer 先关闭再回调）
  final VoidCallback onCreate;

  /// 删除会话（批次73：长按会话 → 确认 → drawer 先关闭再回调；null 时无删除入口）
  final ValueChanged<String>? onDelete;

  const SessionDrawer({
    super.key,
    required this.sessions,
    required this.currentSessionId,
    required this.onSelect,
    required this.onCreate,
    this.onDelete,
  });

  /// 阶段标签文案（对齐 RN PHASE_LABELS）
  static String? phaseLabel(String? phase) {
    return switch (TeachingPhase.fromString(phase)) {
      TeachingPhase.p0Engage => '建立投入',
      TeachingPhase.p1World => '暴露问题',
      TeachingPhase.p2PracticeLoop => '训练循环',
      TeachingPhase.p3Training => '深度训练',
      TeachingPhase.p4Review => '复盘阶段',
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surfaceWhite,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部 ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
              ),
              child: const Text(
                '对话',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            // ── 列表 / 空态 ──
            Expanded(
              child: sessions.isEmpty
                  ? _buildEmpty(context)
                  : ListView.separated(
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.borderSoft),
                      itemBuilder: (context, index) =>
                          _buildSessionCard(context, sessions[index]),
                    ),
            ),
            // ── 底部新建 ──
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSoft)),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onCreate();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '新建会话',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空态（对齐 RN EmptyState：还没有会话 / 发起第一次对话）
  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            size: 40,
            color: AppColors.disabledText,
          ),
          const SizedBox(height: 12),
          const Text(
            '还没有会话',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '发起你的第一次对话，开始写作诊断之旅',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onCreate();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: const Text('发起第一次对话'),
          ),
        ],
      ),
    );
  }

  /// 会话卡片（对齐 RN sessionCard：avatar + 标题 + 时间 + 预览 + 阶段标签）
  Widget _buildSessionCard(BuildContext context, SessionWithPhase item) {
    final isActive = item.session.id == currentSessionId;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onSelect(item.session.id);
      },
      // 批次73：长按会话 → 删除确认（对齐消息长按删除心智）
      onLongPress: onDelete != null
          ? () => _confirmDelete(context, item)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 月字头像
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '月',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? AppColors.onPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 内容区
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.session.title.isEmpty
                              ? '新建会话'
                              : item.session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRelativeTime(item.session.updatedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.session.preview.isEmpty
                              ? '暂无消息'
                              : item.session.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      if (phaseLabel(item.currentPhase) != null) ...[
                        const SizedBox(width: 8),
                        _phaseTag(phaseLabel(item.currentPhase)!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 删除会话确认（批次73）：确认后关抽屉 → 回调 onDelete
  Future<void> _confirmDelete(
    BuildContext context,
    SessionWithPhase item,
  ) async {
    final title = item.session.title.isEmpty ? '新建会话' : item.session.title;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.overlay,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '删除会话',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          '删除「$title」？该会话的全部对话记录将一并删除，此操作不可撤销。',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text(
              '取消',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text(
              '删除',
              style: TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop(); // 关闭抽屉
      onDelete?.call(item.session.id);
    }
  }

  /// 阶段标签（月色竹青：竹青淡底 + 竹青字）
  Widget _phaseTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
