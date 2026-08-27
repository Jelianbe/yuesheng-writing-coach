// ─────────────────────────────────────────────────────────────
// RecycleBinSheet — 回收板弹层（批次86-1 回收板）
// 对标写作天下「回收板」：删除/剪切的长文本找回，防误删。
//
// 交互：
//   - 列表显示最近删除/剪切的文本（内容预览 + 字数 + 时间）
//   - 点击条目 → 关闭弹层 + onRestore 回调（页面在光标处恢复）
//   - 行尾删除按钮 → 移除单条；右上角清空 → 一键清空
// 存储走 app_state key-value（recycle_bin JSON 数组，零 schema 改动）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/app_state_repository.dart';
import '../providers/app_providers.dart';
import 'yue_sheet.dart';

class RecycleBinSheet extends ConsumerStatefulWidget {
  /// 点击条目 → 关闭弹层 + 回调（页面在光标处恢复文本并保存）
  final ValueChanged<String> onRestore;

  const RecycleBinSheet({super.key, required this.onRestore});

  /// 打开回收板弹层
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onRestore,
  }) {
    return showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => RecycleBinSheet(onRestore: onRestore),
    );
  }

  @override
  ConsumerState<RecycleBinSheet> createState() => _RecycleBinSheetState();
}

class _RecycleBinSheetState extends ConsumerState<RecycleBinSheet> {
  /// null = 加载中
  List<RecycleBinItem>? _items;

  /// 批次87-2：恢复后自动移除该条（用户级开关，默认关）
  bool _removeOnRestore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    final items = await repo.listRecycleBinItems();
    final removeOnRestore = await repo.getRecycleBinRemoveOnRestore();
    if (!mounted) return;
    setState(() {
      _items = items;
      _removeOnRestore = removeOnRestore;
    });
  }

  Future<void> _removeAt(int index) async {
    await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).removeRecycleBinItemAt(index);
    await _load();
  }

  Future<void> _clearAll() async {
    await AppStateRepository(ref.read(appDatabaseProvider)).clearRecycleBin();
    await _load();
  }

  void _toggleRemoveOnRestore(bool on) {
    setState(() => _removeOnRestore = on);
    AppStateRepository(
      ref.read(appDatabaseProvider),
    ).setRecycleBinRemoveOnRestore(on);
  }

  /// 点击条目 → 关闭 + 回调页面恢复（开关开启时先移除该条）
  Future<void> _restore(int index) async {
    final items = _items;
    if (items == null || index < 0 || index >= items.length) return;
    final item = items[index];
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    if (_removeOnRestore) {
      await repo.removeRecycleBinItemAt(index);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onRestore(item.content);
  }

  String _formatTime(int unixSec) {
    final t = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final mo = t.month.toString().padLeft(2, '0');
    return '$mo-$dd $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.md,
        AppSpacing.section,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '回收板',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textInk,
                ),
              ),
              const Spacer(),
              if (items != null && items.isNotEmpty)
                IconButton(
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  tooltip: '清空回收板',
                  onPressed: _clearAll,
                ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('删掉或剪切的长文本会留在这里，点一下就能找回', style: AppTextStyles.caption),
          // 批次87-2：恢复后自动移除开关
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('恢复后自动移除该条', style: AppTextStyles.subBody),
            value: _removeOnRestore,
            activeTrackColor: AppColors.primary,
            onChanged: _toggleRemoveOnRestore,
          ),
          const SizedBox(height: 8),
          SizedBox(height: 300, child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    final items = _items;
    if (items == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 36, color: AppColors.placeholder),
            SizedBox(height: 8),
            Text(
              '回收板是空的\n删掉的长文本会自动留在这里',
              textAlign: TextAlign.center,
              style: AppTextStyles.subCaption,
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: () => _restore(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.content.length} 字 · ${_formatTime(item.deletedAt)}',
                        style: AppTextStyles.microCaption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  tooltip: '移除',
                  onPressed: () => _removeAt(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
