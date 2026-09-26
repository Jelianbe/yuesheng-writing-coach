// ─────────────────────────────────────────────────────────────
// RelatedSessionsTab — 作品详情页「相关对话」Tab（批次 28）
//
// 数据源：SessionRepository.listRelatedSessions(manuscriptId)
//   命中本书（session_reference 引用本书/本书章节，或 sessions.manuscript_id 缓存）
//   按活跃度（updated_at DESC）排序
//
// 列表项（对齐 SessionDrawer sessionCard）：
//   月字头像 + 会话标题 + 阶段标签 + 预览 + 相对时间
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/repositories/session_repository.dart';
import '../../providers/app_providers.dart';
import '../../utils/time_format.dart';
import '../../theme/app_typography.dart';

class RelatedSessionsTab extends ConsumerStatefulWidget {
  final String manuscriptId;

  /// 批次 30：点击会话 → 打开对话页并切换该会话（由详情页接线）
  final void Function(String sessionId) onOpenSession;

  const RelatedSessionsTab({
    super.key,
    required this.manuscriptId,
    required this.onOpenSession,
  });

  @override
  ConsumerState<RelatedSessionsTab> createState() => _RelatedSessionsTabState();
}

class _RelatedSessionsTabState extends ConsumerState<RelatedSessionsTab> {
  bool _loading = true;
  List<SessionWithPhase> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = SessionRepository(ref.read(appDatabaseProvider));
    final sessions = await repo.listRelatedSessions(widget.manuscriptId);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.palette.primary),
      );
    }
    if (_sessions.isEmpty) return _buildEmpty(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _sessions.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: context.palette.borderSoft),
      itemBuilder: (context, index) => _buildSessionCard(_sessions[index]),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: context.palette.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有相关对话',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '通过本书发起对话，或在对话中引用本书内容后，\n对话会按活跃度显示在这里',
              textAlign: TextAlign.center,
              style: context.text.subCaption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(SessionWithPhase item) {
    return InkWell(
      onTap: () => widget.onOpenSession(item.session.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            _buildSessionAvatar(),
            const SizedBox(width: 12),
            Expanded(child: _buildSessionContent(item)),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.palette.surface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '月',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: context.palette.textTertiary,
        ),
      ),
    );
  }

  Widget _buildSessionContent(SessionWithPhase item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.session.title.isEmpty ? '新建会话' : item.session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatRelativeTime(item.session.updatedAt),
              style: TextStyle(
                fontSize: 12,
                color: context.palette.textTertiary,
              ),
            ),
          ],
        ),
        if (item.session.preview.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            item.session.preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.subBody,
          ),
        ],
      ],
    );
  }
}
