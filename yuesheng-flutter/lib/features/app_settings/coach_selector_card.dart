// ─────────────────────────────────────────────────────────────
// coach_selector_card — 教练人格（全局，设置页）
//
// 三档内置教练（豆包温和 / 月笙如歌 / sensei 严格）本就在聊天头部可切换，
// 这里把它们提成设置页里**有说明**的卡片，并在底部标注「自定义教练」入口（下批）。
// 选择写入 coach_attitude KV，下次启动自动沿用
// （chat_attitude_controller.loadAttitude 读取后覆盖 session 级态度）。
// 态度色沿用 App 既有语义：doubao=l1Text / yuesheng=l2Text / sensei=l3Text。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../providers/app_providers.dart';
import '../../types/teaching_types.dart';

class CoachSelectorCard extends ConsumerStatefulWidget {
  const CoachSelectorCard({super.key});

  @override
  ConsumerState<CoachSelectorCard> createState() => _CoachSelectorCardState();
}

class _CoachSelectorCardState extends ConsumerState<CoachSelectorCard> {
  String? _current;
  bool _loading = true;

  /// 内置教练（态度级 + 名称 + 一句话声音描述），顺序即展示顺序。
  static const _coaches = [
    (AttitudeLevel.doubao, '豆包', '温和，先肯定再给建议，适合刚起步'),
    (AttitudeLevel.yuesheng, '月笙如歌', '有主张但不冷硬，平衡鼓励与指正'),
    (AttitudeLevel.sensei, 'sensei', '严格，直指问题、不留情面'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await AppStateRepository(
        ref.read(appDatabaseProvider),
      ).getCoachAttitude();
      final parsed = raw == null ? null : AttitudeLevel.fromString(raw);
      if (!mounted) return;
      setState(() {
        _current = parsed?.name;
        _loading = false;
      });
    } catch (_) {
      // 读不到（测试/异常）→ 不渲染卡片，不阻塞设置页
    }
  }

  Future<void> _select(AttitudeLevel level) async {
    try {
      await AppStateRepository(
        ref.read(appDatabaseProvider),
      ).setCoachAttitude(level.name);
      if (mounted) setState(() => _current = level.name);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('教练切换失败，请稍后再试')));
      }
    }
  }

  Color _attitudeColor(AppPalette p, AttitudeLevel a) => switch (a) {
    AttitudeLevel.doubao => p.l1Text,
    AttitudeLevel.yuesheng => p.l2Text,
    AttitudeLevel.sensei => p.l3Text,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(palette),
          const SizedBox(height: 4),
          Text(
            '换一种说话方式。切换后下次启动沿用。',
            style: TextStyle(fontSize: 13, color: palette.textTertiary),
          ),
          const SizedBox(height: 12),
          for (final (level, name, desc) in _coaches)
            _coachRow(
              context,
              level: level,
              name: name,
              desc: desc,
              selected: _current == level.name,
              onTap: () => _select(level),
            ),
          const SizedBox(height: 10),
          Text(
            '自定义教练（从模板复制、改 prompt、换图标）下批。',
            style: TextStyle(fontSize: 11, color: palette.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(AppPalette palette) => Row(
    children: [
      Icon(Icons.psychology_outlined, size: 18, color: palette.primary),
      const SizedBox(width: 6),
      Text(
        '教练人格',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '全局',
          style: TextStyle(fontSize: 11, color: palette.primary),
        ),
      ),
    ],
  );

  Widget _coachRow(
    BuildContext context, {
    required AttitudeLevel level,
    required String name,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    final color = _attitudeColor(palette, level);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? palette.primary : palette.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            _coachNameDesc(palette, name, desc),
            if (selected)
              Icon(Icons.check_circle, size: 18, color: palette.primary),
          ],
        ),
      ),
    );
  }

  Widget _coachNameDesc(AppPalette palette, String name, String desc) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ],
        ),
      );
}
