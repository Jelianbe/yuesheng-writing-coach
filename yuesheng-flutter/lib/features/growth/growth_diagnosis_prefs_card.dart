// ─────────────────────────────────────────────────────────────
// growth_diagnosis_prefs_card — 诊断编辑器：成长页偏好管理
//
// 展示：档位选择（写作阶段 × 写什么）+ 已关闭症候列表 + 恢复。
// 用户在这里选档，诊断时按档过滤症候；诊断卡里关的也能在这里开回来。
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

const _tiers = [('beginner', '先写顺'), ('story', '完整故事'), ('full', '想被挑刺')];

const _genres = [
  ('literary', '纯文学'),
  ('webnovel', '连载网文'),
  ('setting', '设定优先'),
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
    final disabled = cur.disabledIds;
    return GrowthInfoCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerRow(context, cur, disabled),
            const SizedBox(height: 10),
            Text(
              '你写到哪了？',
              style: TextStyle(fontSize: 13, color: context.palette.l2Text),
            ),
            const SizedBox(height: 6),
            _chipRow(
              context,
              selected: cur.tier,
              options: _tiers,
              onSelect: (v) => _save(cur.copyWith(tier: v, customized: true)),
            ),
            const SizedBox(height: 10),
            Text(
              '主要写什么？',
              style: TextStyle(fontSize: 13, color: context.palette.l2Text),
            ),
            const SizedBox(height: 6),
            _chipRow(
              context,
              selected: cur.genre,
              options: _genres,
              onSelect: (v) => _save(cur.copyWith(genre: v, customized: true)),
            ),
            if (disabled.isNotEmpty) ..._disabledList(context, disabled),
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
    return Row(
      children: [
        Icon(Icons.tune_outlined, size: 18, color: context.palette.primary),
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
        if (disabled.isNotEmpty || cur.tier != null || cur.genre != null)
          TextButton(
            onPressed: _restoreAll,
            child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _chipRow(
    BuildContext context, {
    required String? selected,
    required List<(String, String)> options,
    required void Function(String) onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final (id, label) in options)
          ChoiceChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            selected: selected == id,
            onSelected: (_) => onSelect(id),
            selectedColor: context.palette.primarySoft,
          ),
      ],
    );
  }

  List<Widget> _disabledList(BuildContext context, Set<String> disabled) {
    return [
      const SizedBox(height: 14),
      Text(
        '已关闭 ${disabled.length} 项',
        style: TextStyle(fontSize: 13, color: context.palette.l3Text),
      ),
      const SizedBox(height: 4),
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
}
