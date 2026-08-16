// ─────────────────────────────────────────────────────────────
// QuickPhraseSheet — 快捷短语弹层（批次85-3 快捷短语）
// 对标起点/笔落/灯果「快捷短语/常用语」：常用语管理 + 光标一键插入。
//
// 交互：
//   - 顶部输入框 + 「添加」→ 存为常用语（去重，上限 30）
//   - 列表显示已有短语 → 点击插入到光标位置（关闭弹层 + onInsert 回调交页面）
//   - 列表行删除按钮 → 移除
// 存储走 app_state key-value（quick_phrases JSON 数组，零 schema 改动）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/app_state_repository.dart';
import '../providers/app_providers.dart';
import 'yue_sheet.dart';

class QuickPhraseSheet extends ConsumerStatefulWidget {
  /// 点击短语 → 关闭弹层 + 回调（页面在光标处插入并保存）
  final ValueChanged<String> onInsert;

  const QuickPhraseSheet({super.key, required this.onInsert});

  /// 打开快捷短语弹层
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onInsert,
  }) {
    return showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => QuickPhraseSheet(onInsert: onInsert),
    );
  }

  @override
  ConsumerState<QuickPhraseSheet> createState() => _QuickPhraseSheetState();
}

class _QuickPhraseSheetState extends ConsumerState<QuickPhraseSheet> {
  /// null = 加载中
  List<String>? _phrases;
  late final TextEditingController _inputCtrl;

  @override
  void initState() {
    super.initState();
    _inputCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final phrases = await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).listQuickPhrases();
    if (!mounted) return;
    setState(() => _phrases = phrases);
  }

  Future<void> _add() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    await repo.addQuickPhrase(text);
    _inputCtrl.clear();
    await _load();
  }

  Future<void> _remove(String phrase) async {
    await AppStateRepository(ref.read(appDatabaseProvider))
        .removeQuickPhrase(phrase);
    await _load();
  }

  /// 点击短语 → 关闭 + 回调页面插入
  void _insert(String phrase) {
    Navigator.of(context).pop();
    widget.onInsert(phrase);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '快捷短语',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textInk,
                ),
              ),
              const Spacer(),
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
          const SizedBox(height: 8),
          // 添加行：输入 + 添加
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textInk,
                  ),
                  decoration: InputDecoration(
                    hintText: '写一句常用的话，点一下就能插入',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.hintText,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.borderSoft),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.borderSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: _add,
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text('添加', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '最多记 30 条，点击短语就会插入到光标位置',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 300, child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    final phrases = _phrases;
    if (phrases == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }
    if (phrases.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_quote, size: 36, color: AppColors.placeholder),
            SizedBox(height: 8),
            Text(
              '还没有快捷短语\n把常写的句子记下来，下次一点就出来',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: phrases.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final phrase = phrases[index];
        return InkWell(
          onTap: () => _insert(phrase),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    phrase,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textInk,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  tooltip: '删除',
                  onPressed: () => _remove(phrase),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
