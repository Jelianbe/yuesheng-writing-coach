// ─────────────────────────────────────────────────────────────
// SettingEntryListView — 「其他」开放容器（设定资料库第二批）
//
// 替换 SettingLibraryTab 的 _OtherSectionPlaceholder：用户自建类别 +
// 名称 + 自由正文 + 逐条「参与诊断」开关（默认关，勾选后进诊断上下文）。
//
// 与角色/世界观的差异（无薄壳页）：容器内嵌组件，列表头自带「＋ 新建」；
// 不建 provider——ConsumerStatefulWidget + ref.read(appDatabaseProvider)
// 直读仓储（照搬 character 四件套口径）。
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
import 'setting_empty_state.dart';
import 'setting_entry_dialogs.dart';

class SettingEntryListView extends ConsumerStatefulWidget {
  final String manuscriptId;

  const SettingEntryListView({super.key, required this.manuscriptId});

  @override
  ConsumerState<SettingEntryListView> createState() =>
      _SettingEntryListViewState();
}

class _SettingEntryListViewState extends ConsumerState<SettingEntryListView> {
  bool _loading = true;
  bool _error = false;
  List<SettingEntry> _entries = const [];
  Map<String, List<String>> _tagsByEntry = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final repo = SettingEntryRepository(ref.read(appDatabaseProvider));
      final tagRepo = SettingTagRepository(ref.read(appDatabaseProvider));
      final items = await repo.listEntries(widget.manuscriptId);
      final tagMap = <String, List<String>>{};
      for (final e in items) {
        tagMap[e.id] = await tagRepo.listForEntity(
          SettingEntityKind.setting,
          e.id,
        );
      }
      if (!mounted) return;
      setState(() {
        _entries = items;
        _tagsByEntry = tagMap;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _toggleParticipate(SettingEntry entry, bool value) async {
    final repo = SettingEntryRepository(ref.read(appDatabaseProvider));
    await repo.setParticipate(entry.id, value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      // 此前是纯文字「加载失败」无按钮 = 死路（IndexedStack 下切走再切回不重载，
      // 用户只能退出整页）。改为可重试错误态。见 EMPTY-STATE-MATRIX §3.1 判据 6。
      return SettingErrorState(message: '加载设定失败，请重试', onRetry: _load);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(
          child: _entries.isEmpty
              ? _EmptyHint(onCreate: _showCreate)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    0,
                    AppSpacing.page,
                    AppSpacing.page,
                  ),
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _EntryCard(
                    entry: _entries[i],
                    tags: _tagsByEntry[_entries[i].id] ?? const [],
                    onToggle: _toggleParticipate,
                    onTap: () => _showEdit(_entries[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xs,
        AppSpacing.page,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '其他设定（${_entries.length}）',
              style: AppTextStyles.titleMd,
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _showCreate(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('＋ 新建设定'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreate() async {
    final created = await showSettingEntryDialog(
      context,
      ref,
      manuscriptId: widget.manuscriptId,
    );
    if (created == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已创建设定，可打标签、关联设定或补充内容')));
      await _load();
    }
  }

  Future<void> _showEdit(SettingEntry entry) async {
    final changed = await showSettingEntryDialog(
      context,
      ref,
      manuscriptId: widget.manuscriptId,
      existing: entry,
    );
    if (changed == true) await _load();
  }
}

/// 空态引导（新建入口与列表头按钮共用）。
///
/// 2026-09-20 观感批：改用公共 [SettingEmptyState]，与角色 / 大纲 / 世界观
/// 三页形态统一（图标 → 标题 → 说明 → 主 CTA）。**文案与动作不变**。
class _EmptyHint extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyHint({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return SettingEmptyState(
      icon: Icons.bookmark_border,
      title: '还没有其他设定',
      description: '记录武器、规则、组织等自定义设定；勾选「参与诊断」后进入诊断上下文。',
      actionLabel: '新建第一条',
      onAction: onCreate,
    );
  }
}

/// 条目卡：类别徽标 + 名称 + 标签 + 正文摘要 + 参与诊断开关。
class _EntryCard extends StatelessWidget {
  final SettingEntry entry;
  final List<String> tags;
  final Future<void> Function(SettingEntry, bool) onToggle;
  final VoidCallback onTap;

  const _EntryCard({
    required this.entry,
    required this.tags,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final category = entry.category.trim();
    final summary = entry.description.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitleRow(category),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final tag in tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text('#$tag', style: AppTextStyles.caption),
                      ),
                  ],
                ),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  summary,
                  style: AppTextStyles.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow(String category) {
    return Row(
      children: [
        if (category.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(category, style: AppTextStyles.caption),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Text(
            entry.name,
            style: AppTextStyles.titleMd,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text('参与诊断', style: AppTextStyles.caption),
        Switch(
          value: entry.participate,
          onChanged: (v) => onToggle(entry, v),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}
