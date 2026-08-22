// ─────────────────────────────────────────────────────────────
// ExcerptPickerSheet — A-3 方案 Y：手动选段弹层（段落级）
//
// 让用户把主引用章节的「选段锚点」（ADR-A3：{chapterId,startPara,endPara}）
// 真正写入 session_reference.excerpt_range——段落窗口基建（方案 X）的
// 唯一写入 UI。
//
// 交互（段落分行列表，点击选择）：
//   - 点空段落      → 单段选区
//   - 点选区外      → 向左/右扩展区间
//   - 点选区内      → 重锚到该段（重新选起点）
//   - 清除选段      → 清空选区（确定后 = 分析整章）
// 语义与 lib/services/paragraph_selection.dart updateParagraphSelection 一致。
//
// 返回值（pop result）：
//   - 用户点「确定」→ ExcerptPickResult（anchor 为 null 表示清除选段）
//   - 取消/下滑关闭 → null（调用方不做任何写库）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../providers/capability_providers.dart';
import '../services/paragraph_selection.dart';

/// 选段确认结果（区分「清除选段」与「取消关闭」——两者 pop 值不能同为 null）
class ExcerptPickResult {
  /// 选段锚点；null 表示用户选择清除选段（恢复整章分析）
  final ({String chapterId, int startPara, int endPara})? anchor;

  const ExcerptPickResult(this.anchor);
}

class ExcerptPickerSheet extends ConsumerStatefulWidget {
  /// 章节主键（锚点 chapterId 来源，即 session_reference.ref_id）
  final String chapterId;

  final String chapterTitle;

  /// 章节正文（以 \n 分段展示）
  final String content;

  /// 既有 excerpt_range JSON（打开时预选；null = 当前无选段）
  final String? initialAnchorJson;

  const ExcerptPickerSheet({
    super.key,
    required this.chapterId,
    required this.chapterTitle,
    required this.content,
    this.initialAnchorJson,
  });

  @override
  ConsumerState<ExcerptPickerSheet> createState() => _ExcerptPickerSheetState();
}

class _ExcerptPickerSheetState extends ConsumerState<ExcerptPickerSheet> {
  List<String> _paras = const [];
  int? _selStart;
  int? _selEnd;

  @override
  void initState() {
    super.initState();
    _paras = widget.content.isEmpty
        ? const <String>[]
        : widget.content.split('\n');
    // 预选：已有锚点且指向本章节时回显（越界 clamp 由展示层兜底）
    // 消费层经 materialCapabilityProvider 注入能力，不直接依赖顶层纯函数。
    final anchor = ref
        .read(materialCapabilityProvider)
        .parseParagraphAnchor(widget.initialAnchorJson);
    if (anchor != null && anchor.chapterId == widget.chapterId) {
      if (anchor.startPara < _paras.length) {
        _selStart = anchor.startPara;
        _selEnd = anchor.endPara.clamp(anchor.startPara, _paras.length - 1);
      }
    }
  }

  bool get _hasSelection => _selStart != null && _selEnd != null;

  void _handleTap(int index) {
    setState(() {
      final (s, e) = updateParagraphSelection(_selStart, _selEnd, index);
      _selStart = s;
      _selEnd = e;
    });
  }

  void _handleClear() {
    setState(() {
      _selStart = null;
      _selEnd = null;
    });
  }

  void _handleConfirm() {
    final anchor = _hasSelection
        ? (
            chapterId: widget.chapterId,
            startPara: _selStart!,
            endPara: _selEnd!,
          )
        : null;
    Navigator.of(context).pop(ExcerptPickResult(anchor));
  }

  String get _statusLabel {
    if (!_hasSelection) return '未选择：对话将分析整章内容';
    final chars = selectionCharCount(_paras, _selStart!, _selEnd!);
    return _selStart == _selEnd
        ? '已选第 ${_selStart! + 1} 段（$chars 字）'
        : '已选第 ${_selStart! + 1}–${_selEnd! + 1} 段（$chars 字）';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '选段：${widget.chapterTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '点击段落选择重点分析范围：点区间外扩展，点区间内重选',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: _paras.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      '本章暂无内容',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.disabledText),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < _paras.length; i++)
                          _buildParaRow(i),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),
          const Divider(height: 1, color: AppColors.borderSoft),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _statusLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_hasSelection)
                      TextButton(
                        onPressed: _handleClear,
                        child: const Text(
                          '清除选段',
                          style: TextStyle(color: AppColors.textTertiary),
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        '取消',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _handleConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParaRow(int index) {
    final selected = _hasSelection && index >= _selStart! && index <= _selEnd!;
    final text = _paras[index];
    return InkWell(
      onTap: () => _handleTap(index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.disabledText,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text.isEmpty ? '（空行）' : text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: text.isEmpty
                      ? AppColors.disabledText
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
