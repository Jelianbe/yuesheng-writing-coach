// ─────────────────────────────────────────────────────────────
// growth_diagnosis_prefs_card — 诊断偏好（教练侧重，不关诊断）
//
// 方案 A（见 .ai/reports/2026-09-26-诊断偏好-方案A-ADR.md）：
// - 档位（写作阶段）× 类型（写什么）是「教练侧重」软信号，只提示教练优先强调什么，
//   不剥夺任何诊断（不再硬映射成禁用维度）。
// - 用户真正能关掉的只有「不适用」维度（disabledIds），独立成区，可单条/全部恢复。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../providers/app_providers.dart';
import '../../services/syndrome_registry.dart';
import 'growth_detail_widgets.dart';

String _nameOf(String id) {
  final hit = kSyndromeRegistry.where((s) => s.id == id).firstOrNull;
  return hit?.name ?? id;
}

/// 第一问：写作阶段（教练侧重，非过滤）
const _tiers = [
  ('beginner', '先写顺', '把基础语病讲透，结构与节奏先不急'),
  ('story', '完整故事', '文字、角色、结构都管'),
  ('full', '想被挑刺', '全开，连细微毛病也点出来'),
];

/// 第二问：主要写什么（教练侧重，非过滤）
const _genres = [
  ('literary', '纯文学', '重语言质感与文风'),
  ('webnovel', '连载网文', '重节奏与读者追更感'),
  ('setting', '设定优先', '重世界观与人物'),
];

class GrowthDiagnosisPrefsCard extends ConsumerStatefulWidget {
  const GrowthDiagnosisPrefsCard({super.key});

  @override
  ConsumerState<GrowthDiagnosisPrefsCard> createState() =>
      _GrowthDiagnosisPrefsCardState();
}

class _GrowthDiagnosisPrefsCardState
    extends ConsumerState<GrowthDiagnosisPrefsCard> {
  DiagnosisPrefs? _prefs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await AppStateRepository(
        ref.read(appDatabaseProvider),
      ).getDiagnosisPrefs();
      if (mounted) {
        setState(() {
          _prefs = p;
          _loading = false;
        });
      }
    } catch (_) {
      // 读不到偏好（测试/异常）→ 不渲染卡片，不阻塞页面
    }
  }

  Future<void> _save(DiagnosisPrefs next) async {
    await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).setDiagnosisPrefs(next);
    if (mounted) setState(() => _prefs = next);
  }

  Future<void> _restoreOne(String id) async {
    final cur = _prefs ?? DiagnosisPrefs();
    _save(cur.copyWith(disabledIds: {...cur.disabledIds}..remove(id)));
  }

  Future<void> _restoreAll() => _save(DiagnosisPrefs());

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final cur = _prefs ?? DiagnosisPrefs();
    return _buildBody(context, cur);
  }

  Widget _buildBody(BuildContext context, DiagnosisPrefs cur) {
    final palette = context.palette;
    final disabled = cur.disabledIds;
    return GrowthInfoCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(context, cur, disabled),
            const SizedBox(height: 6),
            Text(
              '告诉教练你现在的阶段和题材，它会更侧重对应方向——'
              '但不会因此跳过任何诊断。',
              style: TextStyle(fontSize: 12, color: palette.textTertiary),
            ),
            const SizedBox(height: 14),
            _groupLabel(context, '你写到哪了？'),
            ..._tiers.map(
              (t) => _optionRow(
                context,
                label: t.$2,
                desc: t.$3,
                selected: cur.tier == t.$1,
                onTap: () => _save(cur.copyWith(tier: t.$1, customized: true)),
              ),
            ),
            const SizedBox(height: 12),
            _groupLabel(context, '主要写什么？'),
            ..._genres.map(
              (g) => _optionRow(
                context,
                label: g.$2,
                desc: g.$3,
                selected: cur.genre == g.$1,
                onTap: () => _save(cur.copyWith(genre: g.$1, customized: true)),
              ),
            ),
            if (disabled.isNotEmpty) ..._disabledSection(context, disabled),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(
    BuildContext context,
    DiagnosisPrefs cur,
    Set<String> disabled,
  ) {
    final palette = context.palette;
    return Row(
      children: [
        Icon(Icons.tune_outlined, size: 18, color: palette.primary),
        const SizedBox(width: 6),
        Text(
          '诊断偏好',
          style: TextStyle(
            fontSize: 15,
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
            '教练侧重',
            style: TextStyle(fontSize: 11, color: palette.primary),
          ),
        ),
        const Spacer(),
        if (disabled.isNotEmpty || cur.tier != null || cur.genre != null)
          TextButton(
            onPressed: _restoreAll,
            child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _groupLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.palette.textSecondary,
          ),
        ),
      );

  Widget _optionRow(
    BuildContext context, {
    required String label,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
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
          border: Border.all(color: selected ? palette.primary : palette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
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
            ),
            if (selected) Icon(Icons.check_circle, size: 18, color: palette.primary),
          ],
        ),
      ),
    );
  }

  List<Widget> _disabledSection(BuildContext context, Set<String> disabled) {
    final palette = context.palette;
    return [
      const SizedBox(height: 14),
      Divider(height: 1, color: palette.borderSoft),
      const SizedBox(height: 12),
      Row(
        children: [
          Icon(Icons.block_outlined, size: 16, color: palette.danger),
          const SizedBox(width: 6),
          Text(
            '你关掉的维度（不适用）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...disabled.map(
        (id) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.dangerBg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: palette.dangerBorder),
                ),
                child: Text(
                  _nameOf(id),
                  style: TextStyle(fontSize: 12, color: palette.danger),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _restoreOne(id),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('恢复', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
