// ─────────────────────────────────────────────────────────────
// VersionTimeMachineSheet — 版本时光机弹层（批次82 P0 四件套之③ + 批次84-3 差异对比）
//
// 数据安全感：每 200 字自动落一章版本快照（WritingStore saveNow 时触发），
// 此弹层浏览历史版本并可一键恢复（恢复前当前内容先存为新版本，不丢稿）。
//
// 入口：写作页 ⋮ 更多菜单 →「版本时光机」。
//
// 交互（列表 ↔ 详情同层切换，避免弹层上叠对话框的双层路由问题）：
//   - 列表新→旧：时间 + 字数 + 首行摘要
//   - 点版本行 → 进入详情（全文预览 + 差异对比 + 恢复/返回）
//   - 恢复 → 关闭弹层 + onRestore(content)（页面侧完成状态更新 + 保存 + 提示）
//
// 批次84-3：详情全文预览升级为「与当前内容差异对比」——相对当前内容，
// 版本里新增的标绿底、被删掉的标红底划线（轻量 diff，行级 LCS + 变化块内字符级 LCS）。
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/app_state_repository.dart';
import '../providers/app_providers.dart';
import 'yue_sheet.dart';

/// 差异段类型：same=两版共有 / added=版本新增（相对当前）/ removed=当前有而版本删掉的
enum DiffKind { same, added, removed }

/// 单个差异分段（渲染用）
class DiffSegment {
  final String text;
  final DiffKind kind;
  const DiffSegment(this.text, this.kind);
}

/// 轻量差异：行级 LCS 对齐 + 变化块内字符级 LCS，
/// 产出统一内联视图的分段序列（删除段在前、新增段在后、相同段为上下文）。
/// [current] = 当前内容，[version] = 版本内容。
/// 行按「行内带分隔符」（'\n' 归属前一行）拆分，切块/合并后换行逐字保留。
List<DiffSegment> diffText(String current, String version) {
  if (current == version) {
    return [DiffSegment(version, DiffKind.same)];
  }
  final a = _splitLinesKeepSep(current);
  final b = _splitLinesKeepSep(version);
  final out = <DiffSegment>[];
  var i = 0;
  var j = 0;
  for (final (ai, bj) in _lcsLinePairs(a, b)) {
    _emitChange(a.sublist(i, ai).join(), b.sublist(j, bj).join(), out);
    out.add(DiffSegment(a[ai], DiffKind.same));
    i = ai + 1;
    j = bj + 1;
  }
  _emitChange(a.sublist(i).join(), b.sublist(j).join(), out);
  return out;
}

/// 按行拆分并保留行尾分隔符（'\n' 归前一行，最后一行可能无 '\n'）
List<String> _splitLinesKeepSep(String text) {
  final lines = text.split('\n');
  return [
    for (var k = 0; k < lines.length; k++)
      k < lines.length - 1 ? '${lines[k]}\n' : lines[k],
  ];
}

/// 行级 LCS：返回按序相等的 (a 下标, b 下标) 对
List<(int, int)> _lcsLinePairs(List<String> a, List<String> b) {
  final m = a.length;
  final n = b.length;
  final dp = List<int>.filled((m + 1) * (n + 1), 0);
  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      final idx = i * (n + 1) + j;
      dp[idx] = a[i] == b[j]
          ? dp[(i + 1) * (n + 1) + j + 1] + 1
          : math.max(dp[(i + 1) * (n + 1) + j], dp[i * (n + 1) + j + 1]);
    }
  }
  final pairs = <(int, int)>[];
  var i = 0;
  var j = 0;
  while (i < m && j < n) {
    if (a[i] == b[j]) {
      pairs.add((i, j));
      i++;
      j++;
    } else if (dp[(i + 1) * (n + 1) + j] >= dp[i * (n + 1) + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return pairs;
}

/// 变化块 → 字符级 diff 分段（removed 空则整段 added，added 空则整段 removed）
void _emitChange(String removedText, String addedText, List<DiffSegment> out) {
  if (removedText.isEmpty && addedText.isEmpty) return;
  if (removedText.isEmpty) {
    out.add(DiffSegment(addedText, DiffKind.added));
    return;
  }
  if (addedText.isEmpty) {
    out.add(DiffSegment(removedText, DiffKind.removed));
    return;
  }
  out.addAll(_charDiff(removedText, addedText));
}

/// 版本差异角标统计（批次87-4）：相对当前内容，版本新增/删除的字符数 (added, removed)
(int, int) diffCounts(String current, String version) {
  var added = 0;
  var removed = 0;
  for (final s in diffText(current, version)) {
    switch (s.kind) {
      case DiffKind.added:
        added += s.text.length;
      case DiffKind.removed:
        removed += s.text.length;
      case DiffKind.same:
        break;
    }
  }
  return (added, removed);
}

/// 字符级 LCS：删除段在前、新增段在后、相同段原样，相邻同类合并
List<DiffSegment> _charDiff(String removed, String added) {
  const maxLen = 2000; // 防御超长文本退化：整块标为删除+新增
  if (removed.length > maxLen || added.length > maxLen) {
    return [
      DiffSegment(removed, DiffKind.removed),
      DiffSegment(added, DiffKind.added),
    ];
  }
  final m = removed.length;
  final n = added.length;
  final dp = List<int>.filled((m + 1) * (n + 1), 0);
  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      final idx = i * (n + 1) + j;
      dp[idx] = removed.codeUnitAt(i) == added.codeUnitAt(j)
          ? dp[(i + 1) * (n + 1) + j + 1] + 1
          : math.max(dp[(i + 1) * (n + 1) + j], dp[i * (n + 1) + j + 1]);
    }
  }
  final raw = <({String text, DiffKind kind})>[];
  var i = 0;
  var j = 0;
  while (i < m && j < n) {
    if (removed.codeUnitAt(i) == added.codeUnitAt(j)) {
      raw.add((text: removed[i], kind: DiffKind.same));
      i++;
      j++;
    } else if (dp[(i + 1) * (n + 1) + j] >= dp[i * (n + 1) + j + 1]) {
      raw.add((text: removed[i], kind: DiffKind.removed));
      i++;
    } else {
      raw.add((text: added[j], kind: DiffKind.added));
      j++;
    }
  }
  while (i < m) {
    raw.add((text: removed[i], kind: DiffKind.removed));
    i++;
  }
  while (j < n) {
    raw.add((text: added[j], kind: DiffKind.added));
    j++;
  }
  final out = <DiffSegment>[];
  for (final s in raw) {
    if (out.isNotEmpty && out.last.kind == s.kind) {
      out[out.length - 1] = DiffSegment(out.last.text + s.text, s.kind);
    } else {
      out.add(DiffSegment(s.text, s.kind));
    }
  }
  return out;
}

class VersionTimeMachineSheet extends ConsumerStatefulWidget {
  final String chapterId;

  /// 当前编辑器内容（差异对比基准；批次84-3）
  final String currentContent;

  /// 恢复回调（入参为要恢复的版本全文）
  final ValueChanged<String> onRestore;

  const VersionTimeMachineSheet({
    super.key,
    required this.chapterId,
    required this.currentContent,
    required this.onRestore,
  });

  /// 打开版本时光机弹层（批次82；批次84-3 传入当前内容作差异对比基准）
  static Future<void> show(
    BuildContext context, {
    required String chapterId,
    required String currentContent,
    required ValueChanged<String> onRestore,
  }) {
    return showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => VersionTimeMachineSheet(
        chapterId: chapterId,
        currentContent: currentContent,
        onRestore: onRestore,
      ),
    );
  }

  @override
  ConsumerState<VersionTimeMachineSheet> createState() =>
      _VersionTimeMachineSheetState();
}

class _VersionTimeMachineSheetState
    extends ConsumerState<VersionTimeMachineSheet> {
  /// null = 加载中
  List<ChapterVersion>? _versions;

  /// 当前详情查看的版本（null = 列表态）
  ChapterVersion? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final versions = await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).listChapterVersions(widget.chapterId);
    if (!mounted) return;
    setState(() => _versions = versions);
  }

  String _formatTime(int unixSec) {
    final t = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final mo = t.month.toString().padLeft(2, '0');
    return '$mo-$dd $hh:$mm';
  }

  /// 版本摘要：首行非空内容截断 24 字
  String _preview(ChapterVersion v) {
    final firstLine = v.content
        .split('\n')
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return '（空内容）';
    return firstLine.length > 24 ? '${firstLine.substring(0, 24)}…' : firstLine;
  }

  /// 恢复：关闭弹层 + 回调页面侧（页面完成状态更新 + 保存 + 提示）
  void _restore(ChapterVersion v) {
    Navigator.of(context).pop();
    widget.onRestore(v.content);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selected != null ? '版本详情' : '版本时光机',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (_selected == null) ...[
            const SizedBox(height: 4),
            const Text(
              '每 200 字自动保存一个版本，最多保留 50 个',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            width: double.infinity,
            child: _selected != null ? _buildDetail(_selected!) : _buildList(),
          ),
        ],
      ),
    );
  }

  /// 版本详情视图（全文预览 + 差异对比 + 恢复/返回）
  Widget _buildDetail(ChapterVersion v) {
    // 批次84-3：相对当前内容计算差异（版本内容为空时无对比可做，直接占位）
    final hasContent = v.content.isNotEmpty;
    final segments = hasContent
        ? diffText(widget.currentContent, v.content)
        : const <DiffSegment>[];
    final hasDiff = segments.any((s) => s.kind != DiffKind.same);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_formatTime(v.savedAt)} · ${v.wordCount}字',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        const Text(
          '恢复时当前内容会先自动保存为新版本，不会丢失。',
          style: TextStyle(fontSize: 12, color: AppColors.textDeep),
        ),
        if (hasContent) ...[
          const SizedBox(height: 4),
          Text(
            hasDiff ? '相对当前内容：新增标绿 · 删除划线' : '与当前内容一致',
            style: TextStyle(
              fontSize: 12,
              color: hasDiff ? AppColors.textSecondary : AppColors.success,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: hasContent
                  ? _buildDiffBody(segments)
                  : const Text(
                      '（空内容）',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _selected = null),
                child: const Text('返回列表'),
              ),
            ),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () => _restore(v),
                child: const Text('恢复此版本'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 批次84-3：差异分段 → 富文本（新增绿底 / 删除红底划线 / 相同原样）
  Widget _buildDiffBody(List<DiffSegment> segments) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: AppColors.textBody,
        ),
        children: [
          for (final s in segments)
            switch (s.kind) {
              DiffKind.same => TextSpan(text: s.text),
              DiffKind.added => TextSpan(
                text: s.text,
                style: const TextStyle(
                  color: AppColors.success,
                  backgroundColor: AppColors.successBg,
                ),
              ),
              DiffKind.removed => TextSpan(
                text: s.text,
                style: const TextStyle(
                  color: AppColors.danger,
                  backgroundColor: AppColors.dangerBg,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            },
        ],
      ),
    );
  }

  Widget _buildList() {
    final versions = _versions;
    if (versions == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (versions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.history, size: 40, color: AppColors.placeholder),
            SizedBox(height: 8),
            Text(
              '还没有版本记录\n写到 200 字时会自动保存一个版本',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: versions.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final v = versions[index];
        // 批次87-4：相对当前内容的差异量角标（+新增/-删除字符数）
        final (added, removed) = diffCounts(widget.currentContent, v.content);
        return InkWell(
          onTap: () => setState(() => _selected = v),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    _formatTime(v.savedAt),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${v.wordCount}字',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _preview(v),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textInk,
                    ),
                  ),
                ),
                if (added > 0 || removed > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    [
                      if (added > 0) '+$added',
                      if (removed > 0) '-$removed',
                    ].join(' '),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: added > 0 && removed > 0
                          ? AppColors.textTertiary
                          : added > 0
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.placeholder,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
