// ignore_for_file: invalid_use_of_protected_member
part of 'growth_detail_page.dart';

extension _GrowthNav on _GrowthDetailPageState {

  /// 批次77：学习进度入口——查最新会话并传 sessionId（对齐 growth_page 正确实现）。
  /// 修复旧实现 `context.go(progressDetail)` 不传参 → 落入「未提供会话 ID」占位死页。
  Future<void> _openProgressDetail() async {
    try {
      final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
      final sessions = await sessionRepo.listSessions(); // updated_at DESC
      if (sessions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('还没有写作会话，先写一章吧')),
          );
        }
        return;
      }
      if (!mounted) return;
      context.push(
        AppRoutes.progressDetail,
        extra: <String, dynamic>{'sessionId': sessions.first.id},
      );
    } catch (_) {
      // 查询失败静默（不进入死页）
    }
  }

  /// 批次57：打开风格纠正底部弹层（纠错非重写——仅纠正五维坐标）
  Future<void> _openStyleCorrection(BuildContext context) async {
    final profile = ref.read(growthStoreProvider).styleProfile;
    if (profile == null) return;
    await showYueModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      builder: (_) => _StyleCorrectionSheet(
        profile: profile,
        onSave: (updated) async {
          await ref
              .read(growthStoreProvider.notifier)
              .correctStyleProfile(updated);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
