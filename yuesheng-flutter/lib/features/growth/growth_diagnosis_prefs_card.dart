// ─────────────────────────────────────────────────────────────
// growth_diagnosis_prefs_card — 诊断编辑器：成长页偏好管理
//
// 展示：当前档名 + 已关闭症候列表 + 每项「恢复」+ 全局「恢复默认」。
// 这是用户「关错了」的退路——诊断卡确认栏只能关，这里能开回来。
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

String _tierLabel(String? tier) => switch (tier) {
  'beginner' => '先写顺（只查文字层）',
  'story' => '完整故事（文字+角色+结构）',
  'full' => '想被挑刺（全开）',
  _ => '默认（全开）',
};

String _genreLabel(String? genre) => switch (genre) {
  'literary' => '纯文学',
  'webnovel' => '连载网文',
  'setting' => '设定优先（只查角色）',
  _ => '通用',
};

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
    final p = await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).getDiagnosisPrefs();
    if (mounted) {
      setState(() {
        _prefs = p;
        _loading = false;
      });
    }
  }

  Future<void> _restoreOne(String id) async {
    final cur = _prefs ?? DiagnosisPrefs();
    final next = cur.copyWith(disabledIds: {...cur.disabledIds}..remove(id));
    await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).setDiagnosisPrefs(next);
    if (mounted) setState(() => _prefs = next);
  }

  Future<void> _restoreAll() async {
    await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).setDiagnosisPrefs(DiagnosisPrefs());
    if (mounted) setState(() => _prefs = DiagnosisPrefs());
  }

  List<Widget> _buildDisabledList(BuildContext context, Set<String> disabled) {
    return [
      const SizedBox(height: 12),
      Text(
        '已关闭 ${disabled.length} 项',
        style: TextStyle(fontSize: 13, color: context.palette.l3Text),
      ),
      const SizedBox(height: 6),
      ...disabled.map(
        (id) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(_nameOf(id), style: const TextStyle(fontSize: 13)),
              ),
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final disabled = _prefs?.disabledIds ?? const {};
    // 没关任何东西 + 没选过档 → 不渲染（别给新用户看空卡片）
    if (disabled.isEmpty && _prefs?.tier == null && _prefs?.genre == null) {
      return const SizedBox.shrink();
    }

    return GrowthInfoCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune_outlined,
                  size: 18,
                  color: context.palette.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '诊断偏好',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textPrimary,
                  ),
                ),
                const Spacer(),
                if (disabled.isNotEmpty || _prefs?.customized == true)
                  TextButton(
                    onPressed: _restoreAll,
                    child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '档位：${_tierLabel(_prefs?.tier)} · ${_genreLabel(_prefs?.genre)}',
              style: TextStyle(fontSize: 13, color: context.palette.l2Text),
            ),
            if (disabled.isNotEmpty) ..._buildDisabledList(context, disabled),
          ],
        ),
      ),
    );
  }
}
