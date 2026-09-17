// ─────────────────────────────────────────────────────────────
// setting_entry_dialogs — 「其他」设定条目新建/编辑弹窗（第二批）
//
// 正文优先（沿用第四批口径）：名称 + 类别 + 正文大框。
// 类别 = 已有类别 chips + 「新类别…」输入（用户自建，自由字符串）。
// 新建/编辑共用本弹窗：existing == null → 新建；否则编辑。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/setting_entry_repository.dart';
import '../../data/repositories/setting_link_repository.dart'
    show SettingEntityKind;
import '../../data/repositories/setting_tag_repository.dart';
import '../../providers/app_providers.dart';

/// 新建/编辑「其他」设定条目。成功写入返回 true（调用方据此刷新）。
Future<bool?> showSettingEntryDialog(
  BuildContext context,
  WidgetRef ref, {
  required String manuscriptId,
  SettingEntry? existing,
}) async {
  final repo = SettingEntryRepository(ref.read(appDatabaseProvider));
  final categories = await repo.listCategories(manuscriptId);
  if (!context.mounted) return null;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _SettingEntryDialog(
      manuscriptId: manuscriptId,
      existing: existing,
      categories: categories,
    ),
  );
}

class _SettingEntryDialog extends ConsumerStatefulWidget {
  final String manuscriptId;
  final SettingEntry? existing;
  final List<String> categories;

  const _SettingEntryDialog({
    required this.manuscriptId,
    this.existing,
    required this.categories,
  });

  @override
  ConsumerState<_SettingEntryDialog> createState() =>
      _SettingEntryDialogState();
}

class _SettingEntryDialogState extends ConsumerState<_SettingEntryDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _newCategoryCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  String _category = '';
  List<String> _tags = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _descCtrl.text = e.description;
      _category = e.category;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTags(e.id));
    }
  }

  Future<void> _loadTags(String entityId) async {
    final repo = SettingTagRepository(ref.read(appDatabaseProvider));
    final items = await repo.listForEntity(SettingEntityKind.setting, entityId);
    if (!mounted) return;
    setState(() => _tags = items);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _newCategoryCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  String get _resolvedCategory {
    final picked = _category.trim();
    if (picked.isNotEmpty) return picked;
    return _newCategoryCtrl.text.trim();
  }

  void _addTag() {
    final tag = _tagCtrl.text.trim();
    if (tag.isEmpty) return;
    if (_tags.contains(tag)) return;
    setState(() => _tags = [..._tags, tag]);
    _tagCtrl.clear();
  }

  void _removeTag(String tag) {
    setState(() => _tags = [..._tags]..remove(tag));
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final category = _resolvedCategory;
    final description = _descCtrl.text.trim();
    setState(() => _saving = true);
    final repo = SettingEntryRepository(ref.read(appDatabaseProvider));
    final tagRepo = SettingTagRepository(ref.read(appDatabaseProvider));
    final e = widget.existing;
    String entityId;
    if (e == null) {
      entityId = await repo.createEntry(
        manuscriptId: widget.manuscriptId,
        category: category,
        name: name,
        description: description,
      );
    } else {
      await repo.updateEntry(
        e.id,
        category: category,
        name: name,
        description: description,
      );
      entityId = e.id;
    }
    await tagRepo.replaceTags(
      widget.manuscriptId,
      SettingEntityKind.setting,
      entityId,
      _tags,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  /// 标签区（R-019 拆分：chips + 行内输入独立成方法，弹窗字段保持 ≤50 行）。
  Widget _buildTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        Text('标签', style: AppTextStyles.titleMd),
        const SizedBox(height: AppSpacing.xs),
        if (_tags.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => _removeTag(tag),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _tagCtrl,
          decoration: const InputDecoration(
            labelText: '添加标签',
            hintText: '回车添加，如：悬疑 / 关键道具',
            isDense: true,
          ),
          onSubmitted: (_) => _addTag(),
        ),
      ],
    );
  }

  /// 已有类别 chips（R-019 拆分：_buildFields 临界，抽出类别选择）。
  Widget _buildCategoryChips() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final c in widget.categories)
          ChoiceChip(
            label: Text(c),
            selected: _category == c,
            onSelected: (_) =>
                setState(() => _category = _category == c ? '' : c),
          ),
      ],
    );
  }

  Widget _buildFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: '名称',
            hintText: '如：血月刃 / 规则怪谈：镜中人',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // 类别：已有 chips + 自建输入
        if (widget.categories.isNotEmpty) ...[
          _buildCategoryChips(),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextField(
          controller: _newCategoryCtrl,
          decoration: InputDecoration(
            labelText: _category.isEmpty ? '类别（新类别或选上方）' : '新类别（可选）',
            hintText: '如：武器 / 组织 / 规则',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _descCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '设定正文',
            hintText: '自由写作：这条设定的具体内容……',
            alignLabelWithHint: true,
          ),
        ),
        _buildTags(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? '新建设定' : '编辑设定'),
      content: SingleChildScrollView(child: _buildFields()),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}
