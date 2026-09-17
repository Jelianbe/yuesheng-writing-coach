// ─────────────────────────────────────────────────────────────
// setting_tags_section — 条目标签区块（设定资料库·标签批次，第二批）
//
// Codex 式自由多标签：chips 展示 + 行内输入（回车添加）+ chip 尾部删除。
// 覆盖 character / world / setting 三类实体详情/编辑场景，与互链区块同构。
// **不参与诊断注入**（克制清单），纯管理/展示层。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/repositories/setting_link_repository.dart'
    show SettingEntityKind;
import '../../data/repositories/setting_tag_repository.dart';
import '../../providers/app_providers.dart';

/// 详情页/编辑弹窗「标签」区块（可编辑 chips）。
class SettingTagsSection extends ConsumerStatefulWidget {
  final String manuscriptId;
  final SettingEntityKind kind;
  final String entityId;

  const SettingTagsSection({
    super.key,
    required this.manuscriptId,
    required this.kind,
    required this.entityId,
  });

  @override
  ConsumerState<SettingTagsSection> createState() => _SettingTagsSectionState();
}

class _SettingTagsSectionState extends ConsumerState<SettingTagsSection> {
  final _tagCtrl = TextEditingController();
  List<String> _tags = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = SettingTagRepository(ref.read(appDatabaseProvider));
    final items = await repo.listForEntity(widget.kind, widget.entityId);
    if (!mounted) return;
    setState(() => _tags = items);
  }

  Future<void> _add() async {
    final tag = _tagCtrl.text.trim();
    if (tag.isEmpty) return;
    final repo = SettingTagRepository(ref.read(appDatabaseProvider));
    await repo.addTag(widget.manuscriptId, widget.kind, widget.entityId, tag);
    _tagCtrl.clear();
    await _load();
  }

  Future<void> _remove(String tag) async {
    final repo = SettingTagRepository(ref.read(appDatabaseProvider));
    await repo.removeTag(
      widget.manuscriptId,
      widget.kind,
      widget.entityId,
      tag,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('标签', style: AppTextStyles.titleMd),
        const SizedBox(height: AppSpacing.xs),
        if (_tags.isEmpty)
          Text('暂无标签，添加后便于检索归类', style: AppTextStyles.caption)
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => _remove(tag),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _tagCtrl,
          decoration: const InputDecoration(
            labelText: '添加标签',
            hintText: '输入后回车，如：悬疑 / 主角团 / 关键道具',
            isDense: true,
          ),
          onSubmitted: (_) => _add(),
        ),
      ],
    );
  }
}
