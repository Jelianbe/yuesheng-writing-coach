// ─────────────────────────────────────────────────────────────
// SearchReplaceSheet — 全文查找替换（批次84-2 全文查找替换）
// 对标调查报告功能 7：长文修订刚需，Dart 字符串操作实现。
//
// 本章视图：
//   - 查找输入即统计匹配数（N 处）+ 定位到第一个匹配
//   - 上一个/下一个在匹配间循环（编辑器选中匹配 = TextField 里的"高亮"）
//   - 「替换」替换当前匹配、「全部替换」整章替换（即时落库）
// 全书视图：
//   - 「搜索全书」列出各章节命中数与标题，点击跳转到对应章节
//
// 架构：Sheet 持文本副本（打开时快照，模态期间正文不可编辑），
// 落稿/定位经回调交 WritingPage（避免直接改 controller 触发划词菜单误弹）：
//   - onApply(newText, cursorOffset)：替换结果 → 页面写 controller + 保存
//   - onLocate(start, end)：查找定位 → 页面设 selection（抑制划词菜单）
//   - onJumpToChapter：全书结果点击 → 跳转章节（复用批次83-1 机制）
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/chapter_repository.dart';
import '../providers/app_providers.dart';
import 'yue_sheet.dart';

/// 返回 [query] 在 [text] 中所有匹配的起始偏移（无匹配返回空列表）
List<int> computeMatches(String text, String query) {
  if (query.isEmpty || text.isEmpty) return const [];
  final result = <int>[];
  var idx = text.indexOf(query);
  while (idx != -1) {
    result.add(idx);
    idx = text.indexOf(query, idx + query.length);
  }
  return result;
}

/// 批次96-11：命中片段——以首处匹配为中心截取 [radius] 字上下文，截断处补「…」
String buildSnippet(
  String text,
  int matchStart,
  int matchLen, {
  int radius = 20,
}) {
  if (text.isEmpty) return '';
  final start = matchStart - radius < 0 ? 0 : matchStart - radius;
  final end = matchStart + matchLen + radius > text.length
      ? text.length
      : matchStart + matchLen + radius;
  final prefix = start > 0 ? '…' : '';
  final suffix = end < text.length ? '…' : '';
  return '$prefix${text.substring(start, end)}$suffix';
}

class SearchReplaceSheet extends ConsumerStatefulWidget {
  /// 打开时的正文快照（模态期间正文不可编辑，替换后走 onApply 同步）
  final String initialText;

  /// 所属作品（全书搜索用；null/空则隐藏全书入口）
  final String? manuscriptId;

  /// 批次96-11：当前章节 ID（全书结果点击判断"当前章直接定位 vs 跨章跳转"）
  final String currentChapterId;

  /// 替换落稿（newText + 建议光标偏移）
  final void Function(String newText, int cursorOffset) onApply;

  /// 查找定位（start/end → 页面设 selection）
  final void Function(int start, int end) onLocate;

  /// 全书结果点击 → 跳转章节（批次96-11：cursorOffset = 首处命中偏移，跨章定位用）
  final void Function(String chapterId, String chapterTitle, int? cursorOffset)?
  onJumpToChapter;

  /// 批次96-11：true = 打开即全书搜索视图（独立「全文搜索」入口用）
  final bool initialBookView;

  const SearchReplaceSheet({
    super.key,
    required this.initialText,
    required this.manuscriptId,
    required this.currentChapterId,
    required this.onApply,
    required this.onLocate,
    this.onJumpToChapter,
    this.initialBookView = false,
  });

  /// 打开查找替换弹层
  static Future<void> show(
    BuildContext context, {
    required String initialText,
    required String? manuscriptId,
    required String currentChapterId,
    required void Function(String newText, int cursorOffset) onApply,
    required void Function(int start, int end) onLocate,
    void Function(String chapterId, String chapterTitle, int? cursorOffset)?
    onJumpToChapter,
    bool initialBookView = false,
  }) {
    return showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SearchReplaceSheet(
        initialText: initialText,
        manuscriptId: manuscriptId,
        currentChapterId: currentChapterId,
        onApply: onApply,
        onLocate: onLocate,
        onJumpToChapter: onJumpToChapter,
        initialBookView: initialBookView,
      ),
    );
  }

  @override
  ConsumerState<SearchReplaceSheet> createState() => _SearchReplaceSheetState();
}

class _SearchReplaceSheetState extends ConsumerState<SearchReplaceSheet> {
  /// 工作文本副本（替换直接改这里，成功后经 onApply 同步到页面）
  late String _text;
  late final TextEditingController _queryCtrl;
  late final TextEditingController _replaceCtrl;

  List<int> _matches = const [];
  int _current = -1;

  /// true = 全书搜索视图（本章查找替换视图 = false）
  bool _viewAllBook = false;

  /// 全书搜索结果（null = 未加载 / 加载中）
  List<
    ({
      String chapterId,
      String title,
      int count,
      int firstOffset,
      String snippet,
    })
  >?
  _bookResults;

  /// 批次96-11：全书视图防抖定时器（输入即搜，300ms 合并）
  Timer? _bookSearchTimer;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
    _queryCtrl = TextEditingController();
    _replaceCtrl = TextEditingController();
    _queryCtrl.addListener(_onQueryChanged);
    // 批次96-11：独立「全文搜索」入口 → 打开即全书视图 + 自动聚焦查询框
    if (widget.initialBookView) {
      _viewAllBook = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bookSearchTimer?.cancel();
        _bookSearchTimer = Timer(
          const Duration(milliseconds: 300),
          _searchAllBook,
        );
      });
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _replaceCtrl.dispose();
    _bookSearchTimer?.cancel();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _queryCtrl.text;
    if (_viewAllBook) {
      // 批次96-11：全书视图输入 → 防抖触发全书搜索（300ms 合并）
      _bookSearchTimer?.cancel();
      _bookSearchTimer = Timer(
        const Duration(milliseconds: 300),
        _searchAllBook,
      );
      return;
    }
    _runSearch(q);
  }

  /// 重新统计匹配 + 定位到第一个
  void _runSearch(String query) {
    final matches = computeMatches(_text, query);
    setState(() {
      _matches = matches;
      _current = matches.isEmpty ? -1 : 0;
    });
    _locate(_current);
  }

  /// 定位到第 [index] 个匹配（页面侧设 selection 展示）
  void _locate(int index) {
    if (index < 0 || index >= _matches.length) return;
    final start = _matches[index];
    final end = start + _queryCtrl.text.length;
    widget.onLocate(start, end);
  }

  void _next() {
    if (_matches.isEmpty) return;
    setState(() => _current = (_current + 1) % _matches.length);
    _locate(_current);
  }

  void _prev() {
    if (_matches.isEmpty) return;
    setState(
      () => _current = (_current - 1 + _matches.length) % _matches.length,
    );
    _locate(_current);
  }

  /// 替换当前匹配
  void _replaceCurrent() {
    if (_matches.isEmpty || _current < 0 || _current >= _matches.length) return;
    final q = _queryCtrl.text;
    final r = _replaceCtrl.text;
    final start = _matches[_current];
    final newText = _text.replaceRange(start, start + q.length, r);
    final cursor = start + r.length;
    _text = newText;
    widget.onApply(newText, cursor);
    // 重新统计并定位到替换处之后的匹配
    _runSearch(q);
  }

  /// 全部替换（整章）
  void _replaceAll() {
    final q = _queryCtrl.text;
    if (q.isEmpty) return;
    final newText = _text.replaceAll(q, _replaceCtrl.text);
    _text = newText;
    widget.onApply(newText, 0);
    _runSearch(q);
  }

  /// 全书搜索：列出各章节命中数 + 首处命中偏移（批次96-11 增片段/定位）
  Future<void> _searchAllBook() async {
    setState(() => _viewAllBook = true);
    final msId = widget.manuscriptId ?? '';
    if (msId.isEmpty) return;
    final q = _queryCtrl.text;
    if (q.trim().isEmpty) {
      setState(() => _bookResults = const []);
      return;
    }
    final repo = ChapterRepository(ref.read(appDatabaseProvider));
    final chapters = await repo.listChapters(msId);
    if (!mounted) return;
    final results =
        <
          ({
            String chapterId,
            String title,
            int count,
            int firstOffset,
            String snippet,
          })
        >[];
    for (final ch in chapters) {
      // 批次96-11：标题 + 正文都参与匹配（标题命中无正文命中时 snippet 用标题）
      final contentMatches = computeMatches(ch.content, q);
      final titleHit = ch.title.contains(q);
      if (contentMatches.isNotEmpty || titleHit) {
        final title = ch.title.trim().isEmpty ? '未命名章节' : ch.title;
        final snippet = contentMatches.isNotEmpty
            ? buildSnippet(ch.content, contentMatches.first, q.length)
            : (titleHit ? title : '');
        results.add((
          chapterId: ch.id,
          title: title,
          count: contentMatches.length + (titleHit ? 1 : 0),
          firstOffset: contentMatches.isNotEmpty ? contentMatches.first : 0,
          snippet: snippet,
        ));
      }
    }
    if (!mounted) return;
    setState(() => _bookResults = results);
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryCtrl.text;
    final hasMatches = _matches.isNotEmpty;
    final countText = query.isEmpty
        ? ''
        : '${_current + 1}/${_matches.length} 处';
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
              Text(
                // 批次96-11：独立「全文搜索」入口 → 标题显示「全文搜索」
                _viewAllBook && widget.initialBookView ? '全文搜索' : '查找替换',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textInk,
                ),
              ),
              const Spacer(),
              if (widget.manuscriptId != null && !widget.initialBookView)
                TextButton.icon(
                  onPressed: _viewAllBook ? null : _searchAllBook,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.menu_book_outlined, size: 16),
                  label: const Text('搜索全书', style: TextStyle(fontSize: 12)),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 400,
            child: _viewAllBook
                ? _buildBookResults()
                : _buildChapterView(countText, hasMatches),
          ),
        ],
      ),
    );
  }

  /// 本章视图：查找 + 替换
  Widget _buildChapterView(String countText, bool hasMatches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 查找行：输入框 + 上一个/下一个 + 计数
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                controller: _queryCtrl,
                hint: '查找',
                isFind: true,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              tooltip: '上一个',
              onPressed: hasMatches ? _prev : null,
              color: hasMatches
                  ? AppColors.textPrimary
                  : AppColors.disabledText,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              tooltip: '下一个',
              onPressed: hasMatches ? _next : null,
              color: hasMatches
                  ? AppColors.textPrimary
                  : AppColors.disabledText,
            ),
            SizedBox(
              width: 64,
              child: Text(
                countText,
                textAlign: TextAlign.right,
                style: AppTextStyles.noteCaption,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 替换行：输入框 + 替换 + 全部替换
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                controller: _replaceCtrl,
                hint: '替换为',
                isFind: false,
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: hasMatches ? _replaceCurrent : null,
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('替换', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: hasMatches ? _replaceAll : null,
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('全部替换', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('查找会在正文里标出位置，替换后即时保存', style: AppTextStyles.caption),
      ],
    );
  }

  /// 输入框（查找/替换）
  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required bool isFind,
  }) {
    return TextField(
      controller: controller,
      autofocus: isFind,
      style: const TextStyle(fontSize: 14, color: AppColors.textInk),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.hintText),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smx,
          vertical: AppSpacing.sm,
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
    );
  }

  /// 全书视图：查询输入框 + 章节命中列表（批次96-11 增命中片段高亮/定位跳转）
  Widget _buildBookResults() {
    final results = _bookResults;
    final q = _queryCtrl.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 批次96-11：全书视图自带查询框（独立「全文搜索」入口打开即聚焦）
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                controller: _queryCtrl,
                hint: '搜索全书',
                isFind: true,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.search, size: 20),
              tooltip: '搜索',
              onPressed: () {
                _bookSearchTimer?.cancel();
                _searchAllBook();
              },
              color: AppColors.textPrimary,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBookResultList(results, q)),
      ],
    );
  }

  Widget _buildBookResultList(
    List<
      ({
        String chapterId,
        String title,
        int count,
        int firstOffset,
        String snippet,
      })
    >?
    results,
    String q,
  ) {
    if (results == null) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: 36,
              color: AppColors.placeholder,
            ),
            const SizedBox(height: 8),
            Text(
              q.trim().isEmpty ? '输入关键词搜索全书章节' : '全书没有找到相关内容',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final r = results[index];
        return _BookResultTile(
          title: r.title,
          snippet: r.snippet,
          query: q,
          count: r.count,
          onTap: () {
            Navigator.of(context).pop();
            final qLen = q.length;
            if (r.chapterId == widget.currentChapterId) {
              // 当前章：直接定位首处命中（onLocate 设 selection）
              widget.onLocate(r.firstOffset, r.firstOffset + qLen);
            } else {
              // 跨章：跳转并携带首处命中偏移（新页加载后定位）
              widget.onJumpToChapter?.call(r.chapterId, r.title, r.firstOffset);
            }
          },
        );
      },
    );
  }
}

// ── 批次96-11：全书搜索结果项——标题 + 命中片段（关键词高亮）+ 命中数 ──
class _BookResultTile extends StatelessWidget {
  final String title;
  final String snippet;
  final String query;
  final int count;
  final VoidCallback onTap;

  const _BookResultTile({
    required this.title,
    required this.snippet,
    required this.query,
    required this.count,
    required this.onTap,
  });

  /// 片段内所有 query 出现处高亮（primary 色，其余常规）
  TextSpan _buildSnippetSpan() {
    if (query.isEmpty) {
      return TextSpan(text: snippet);
    }
    final spans = <TextSpan>[];
    var idx = 0;
    while (idx < snippet.length) {
      final hit = snippet.indexOf(query, idx);
      if (hit == -1) {
        spans.add(TextSpan(text: snippet.substring(idx)));
        break;
      }
      if (hit > idx) {
        spans.add(TextSpan(text: snippet.substring(idx, hit)));
      }
      spans.add(
        TextSpan(
          text: snippet.substring(hit, hit + query.length),
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      idx = hit + query.length;
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.smx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.article_outlined,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textInk,
                    ),
                  ),
                ),
                Text(
                  '$count 处',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.placeholder,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text.rich(
              _buildSnippetSpan(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.noteCaption.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
