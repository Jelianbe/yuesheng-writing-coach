// ─────────────────────────────────────────────────────────────
// setting_link_dialog — 「添加关联」弹窗（Codex 式互链第一批）
//
// 选择目标类型（角色/世界观/其他/大纲）+ 目标条目（排除自身）+ 可选关系名。
// 返回 SettingLinkTarget（kind + id + label）；取消返回 null。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/character_fact_repository.dart';
import '../../data/repositories/outline_repository.dart';
import '../../data/repositories/setting_entry_repository.dart';
import '../../data/repositories/setting_link_repository.dart';
import '../../data/repositories/world_fact_repository.dart';
import '../../providers/app_providers.dart';

/// 添加关联弹窗的返回值。
class SettingLinkTarget {
  final SettingEntityKind kind;
  final String id;
  final String label;

  const SettingLinkTarget({
    required this.kind,
    required this.id,
    required this.label,
  });
}

/// 目标条目选项（name + id）。
class _TargetOption {
  final String id;
  final String name;

  const _TargetOption(this.id, this.name);
}

/// 打开「添加关联」弹窗。
Future<SettingLinkTarget?> showSettingLinkDialog(
  BuildContext context, {
  required String manuscriptId,
  required SettingEntityKind selfKind,
  required String selfId,
}) {
  return showDialog<SettingLinkTarget>(
    context: context,
    builder: (_) => _SettingLinkDialog(
      manuscriptId: manuscriptId,
      selfKind: selfKind,
      selfId: selfId,
    ),
  );
}

class _SettingLinkDialog extends ConsumerStatefulWidget {
  final String manuscriptId;
  final SettingEntityKind selfKind;
  final String selfId;

  const _SettingLinkDialog({
    required this.manuscriptId,
    required this.selfKind,
    required this.selfId,
  });

  @override
  ConsumerState<_SettingLinkDialog> createState() => _SettingLinkDialogState();
}

class _SettingLinkDialogState extends ConsumerState<_SettingLinkDialog> {
  SettingEntityKind _kind = SettingEntityKind.character;
  final _labelController = TextEditingController();
  String? _selectedId;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _selectKind(SettingEntityKind kind) {
    setState(() {
      _kind = kind;
      _selectedId = null;
    });
  }

  AppDatabase get _db => ref.read(appDatabaseProvider);

  Future<List<_TargetOption>> _loadTargets() async {
    switch (_kind) {
      case SettingEntityKind.character:
        final rows = await CharacterFactRepository(
          _db,
        ).listCharacters(widget.manuscriptId);
        return _toOptions(rows.map((r) => (id: r.id, name: r.name)));
      case SettingEntityKind.world:
        final rows = await WorldFactRepository(
          _db,
        ).listWorlds(widget.manuscriptId);
        return _toOptions(rows.map((r) => (id: r.id, name: r.name)));
      case SettingEntityKind.setting:
        final rows = await SettingEntryRepository(
          _db,
        ).listEntries(widget.manuscriptId);
        return _toOptions(rows.map((r) => (id: r.id, name: r.name)));
      case SettingEntityKind.outline:
        final rows = await OutlineRepository(
          _db,
        ).listEntities(widget.manuscriptId);
        return _toOptions(rows.map((r) => (id: r.id, name: r.entityKey)));
    }
  }

  List<_TargetOption> _toOptions(Iterable<({String id, String name})> rows) {
    final options =
        rows
            .where((r) => r.id != widget.selfId || _kind != widget.selfKind)
            .map((r) => _TargetOption(r.id, r.name))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  /// 目标条目选择列表（R-019 拆分：FutureBuilder + RadioGroup 独立成方法）。
  Widget _buildTargetList() {
    return SizedBox(
      height: 160,
      child: FutureBuilder<List<_TargetOption>>(
        future: _loadTargets(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final options = snapshot.data ?? const [];
          if (options.isEmpty) {
            return const Center(child: Text('该类型暂无条目'));
          }
          return RadioGroup<String>(
            groupValue: _selectedId,
            onChanged: (v) => setState(() => _selectedId = v),
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (_, i) => RadioListTile<String>(
                dense: true,
                value: options[i].id,
                title: Text(options[i].name),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加关联'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<SettingEntityKind>(
              segments: [
                for (final k in SettingEntityKind.values)
                  ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _selectKind(s.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildTargetList(),
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: '关系名（可选）',
                hintText: '如：所属世界 / 宿敌 / 上级组织',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () => Navigator.pop(
                  context,
                  SettingLinkTarget(
                    kind: _kind,
                    id: _selectedId!,
                    label: _labelController.text.trim(),
                  ),
                ),
          child: const Text('添加'),
        ),
      ],
    );
  }
}
