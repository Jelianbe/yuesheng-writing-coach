// ─────────────────────────────────────────────────────────────
// ReferenceBar — 聊天页顶部引用条（缺口清单第 1 项）
// 真源：yuesheng-android/src/components/reference/ReferenceBar.tsx
//
// 结构（对齐 RN）：
//   - 主引用行：库图标 + 主引用标签（作品/章节（主引用））+ 标题
//     + 其它引用数量徽章（+N）+ 展开箭头
//   - 展开列表：refRow（多选框 + 类型标签 + 标题 + 主引用徽章 + 移除按钮）
//   - 多选模式：取消 / 已选 N 项 / 删除选中
//   - 非多选且引用 >1：全选按钮
//   - 「+ 添加引用」虚线按钮（onPressPicker）
//
// 数据：ReferenceCapability.listReferences（带 title 三段 UNION）
// 变更反馈：组件内 SnackBar（message_card_service 无引用变更卡片类型，
// 以提示条代替 RN 的 onReferencesChanged 卡片插入）
// ─────────────────────────────────────────────────────────────

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../contracts/reference_capability.dart';
import '../data/repositories/chapter_repository.dart';
import '../providers/app_providers.dart';
import '../providers/capability_providers.dart';
import 'excerpt_picker_sheet.dart';
import 'yue_sheet.dart';

class ReferenceBar extends ConsumerStatefulWidget {
  /// 会话 ID（引用列表按会话隔离）
  final String sessionId;

  /// 「+ 添加引用」点击 → 打开引用选择器（default 模式）
  final VoidCallback onPressPicker;

  /// 引用变更回调（action: 'set_primary' | 'remove'，单条操作时触发）
  /// 供父级插入 reference_change 卡片（对齐 RN onReferencesChanged）
  final void Function(String action, String refType, String refTitle)?
  onReferencesChanged;

  const ReferenceBar({
    super.key,
    required this.sessionId,
    required this.onPressPicker,
    this.onReferencesChanged,
  });

  @override
  ConsumerState<ReferenceBar> createState() => _ReferenceBarState();
}

class _ReferenceBarState extends ConsumerState<ReferenceBar> {
  bool _expanded = false;
  final Set<String> _selectedRefs = {};
  List<ReferencedItem> _references = [];

  ReferenceCapability get _repo =>
      ref.read(referenceCapabilityProvider);

  @override
  void initState() {
    super.initState();
    _loadReferences();
  }

  @override
  void didUpdateWidget(ReferenceBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      setState(() {
        _expanded = false;
        _selectedRefs.clear();
      });
      _loadReferences();
    }
  }

  Future<void> _loadReferences() async {
    try {
      final refs = await _repo.listReferences(widget.sessionId);
      if (!mounted) return;
      setState(() => _references = refs);
    } catch (_) {
      // 本地查询失败保持空态，静默（release 不暴露技术细节）
    }
  }

  /// 选中键：refType-refId（refId 为 uuid 含 '-'，切分取第一个分隔符）
  String _keyOf(ReferencedItem ref) => '${ref.refType}-${ref.refId}';

  (String, String) _splitKey(String key) {
    final sep = key.indexOf('-');
    return (key.substring(0, sep), key.substring(sep + 1));
  }

  /// 类型标签文案（对齐 RN refTypeLabels）
  String _typeLabel(String refType) => switch (refType) {
    'chapter' => '章节',
    'file' => '素材',
    _ => '作品',
  };

  /// 主引用标签文案（对齐 RN mainLabel）
  String _mainLabel(String refType) => '${_typeLabel(refType)}（主引用）';

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleSetPrimary(ReferencedItem ref) async {
    if (ref.refType == 'file') {
      _notify('素材文件不能设为主引用');
      return;
    }
    try {
      await _repo.setPrimaryReference(widget.sessionId, ref.refType, ref.refId);
      await _loadReferences();
      widget.onReferencesChanged?.call('set_primary', ref.refType, ref.title);
      _notify('已切换到：${ref.title}');
    } catch (_) {
      _notify('操作失败，请稍后再试');
    }
  }

  Future<void> _handleRemove(ReferencedItem ref) async {
    try {
      await _repo.removeReference(widget.sessionId, ref.refType, ref.refId);
      await _loadReferences();
      widget.onReferencesChanged?.call('remove', ref.refType, ref.title);
      _notify('已移除引用：${ref.title}');
    } catch (_) {
      _notify('操作失败，请稍后再试');
    }
  }

  /// A-3 方案 Y：主引用章节「选段」——打开段落选段弹层，
  /// 确认后写入/清除 session_reference.excerpt_range（段落锚点）。
  /// 取消（含下滑关闭）不写库；章节已删除时提示并中止。
  Future<void> _handlePickExcerpt(ReferencedItem item) async {
    final db = this.ref.read(appDatabaseProvider);
    final chapter = await ChapterRepository(db).getChapter(item.refId);
    if (!mounted) return;
    if (chapter == null) {
      _notify('章节不存在或已删除');
      return;
    }
    final result = await showYueModalBottomSheet<ExcerptPickResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExcerptPickerSheet(
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        content: chapter.content,
        initialAnchorJson: item.excerptRange,
      ),
    );
    if (!mounted || result == null) return; // 取消：不写库
    final anchor = result.anchor;
    if (anchor == null && item.excerptRange == null) return; // 无选段可清
    try {
      final hit = await _repo.updateExcerptRange(
        widget.sessionId,
        item.refType,
        item.refId,
        anchor,
      );
      if (!hit) {
        _notify('引用已变更，请重试');
        await _loadReferences();
        return;
      }
      await _loadReferences();
      if (anchor == null) {
        _notify('已清除选段，将分析整章');
      } else if (anchor.startPara == anchor.endPara) {
        _notify('已选段：第 ${anchor.startPara + 1} 段');
      } else {
        _notify(
          '已选段：第 ${anchor.startPara + 1}–${anchor.endPara + 1} 段',
        );
      }
    } catch (_) {
      _notify('操作失败，请稍后再试');
    }
  }

  void _toggleSelect(String key) {
    setState(() {
      if (_selectedRefs.contains(key)) {
        _selectedRefs.remove(key);
      } else {
        _selectedRefs.add(key);
      }
    });
  }

  void _handleSelectAll() {
    setState(() {
      _selectedRefs
        ..clear()
        ..addAll(_references.map(_keyOf));
    });
  }

  void _handleDeselectAll() {
    setState(() => _selectedRefs.clear());
  }

  Future<void> _handleDeleteSelected() async {
    final count = _selectedRefs.length;
    try {
      for (final key in _selectedRefs.toList()) {
        final (refType, refId) = _splitKey(key);
        await _repo.removeReference(widget.sessionId, refType, refId);
      }
      setState(() => _selectedRefs.clear());
      await _loadReferences();
      _notify('已批量删除 $count 项引用');
    } catch (_) {
      _notify('操作失败，请稍后再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryRef = _references.where((r) => r.isPrimary == 1).firstOrNull;
    final otherCount = _references.where((r) => r.isPrimary != 1).length;
    final isSelectMode = _selectedRefs.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        // 批次76：mainAxisSize.min —— 弹层内容自适应高度，不再撑满全屏
        // （isScrollControlled bottom sheet 中 max 会把弹层顶到屏幕顶端侵占状态栏）
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 批次76：标题 + 引用数徽章（弹层可发现性——入口意义一目了然）
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                const Text(
                  '引用管理',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.borderSoft),
                  ),
                  child: Text(
                    '${_references.length} 个引用',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── 主引用行 ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.menu_book_outlined,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: primaryRef != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _mainLabel(primaryRef.refType),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                primaryRef.title.isEmpty
                                    ? '未命名'
                                    : primaryRef.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            // 批次76：空态文案明确引导——点下方「+ 添加引用」按钮
                            '还没有引用作品，点下方按钮添加',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.disabledText,
                            ),
                          ),
                  ),
                  if (otherCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '+$otherCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.disabledText,
                  ),
                ],
              ),
            ),
          ),

          // ── 展开列表 ──
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.borderSoft),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isSelectMode) _buildActionBar(),
                  if (isSelectMode) const SizedBox(height: 4),
                  // 批次76：引用行区域限高可滚动——引用多时弹层不至于溢出屏幕
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final ref in _references)
                            _buildRefRow(ref, isSelectMode),
                        ],
                      ),
                    ),
                  ),
                  if (!isSelectMode && _references.length > 1)
                    _buildSelectAll(),
                  const SizedBox(height: 8),
                  _buildAddRefBtn(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 多选操作条（对齐 RN actionBar）──
  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _handleDeselectAll,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '取消',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '已选 ${_selectedRefs.length} 项',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: _handleDeleteSelected,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '删除选中',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 引用行（对齐 RN refRow）──
  Widget _buildRefRow(ReferencedItem ref, bool isSelectMode) {
    final key = _keyOf(ref);
    final isSelected = _selectedRefs.contains(key);
    return Container(
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primarySoft : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 多选框
          InkWell(
            onTap: () => _toggleSelect(key),
            child: Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : null,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.onPrimary,
                    )
                  : null,
            ),
          ),
          // 引用信息（非多选点击设主引用；多选点击切换选中）
          Expanded(
            child: InkWell(
              onTap: isSelectMode
                  ? () => _toggleSelect(key)
                  : () => _handleSetPrimary(ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _refTypeTag(ref.refType),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ref.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (ref.isPrimary == 1) ...[
                      const SizedBox(width: 8),
                      _primaryBadge(),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 选段按钮（A-3 方案 Y：仅主引用章节显示；多选模式下隐藏）
          if (!isSelectMode &&
              ref.refType == 'chapter' &&
              ref.isPrimary == 1) ...[
            IconButton(
              onPressed: () => _handlePickExcerpt(ref),
              tooltip: '选段',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.content_cut,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ],
          // 移除按钮（多选模式下隐藏）
          if (!isSelectMode)
            IconButton(
              onPressed: () => _handleRemove(ref),
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.disabledText,
              ),
            ),
        ],
      ),
    );
  }

  Widget _refTypeTag(String refType) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.borderSoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        _typeLabel(refType),
        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
      ),
    );
  }

  Widget _primaryBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: const Text(
        '主引用',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.primary,
        ),
      ),
    );
  }

  // ── 全选按钮（对齐 RN selectAllBtn）──
  Widget _buildSelectAll() {
    return InkWell(
      onTap: _handleSelectAll,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            '全选',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  // ── + 添加引用（虚线按钮，对齐 RN addRefBtn）──
  Widget _buildAddRefBtn() {
    return CustomPaint(
      foregroundPainter: const _DashedBorderPainter(),
      child: InkWell(
        onTap: widget.onPressPicker,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              '+ 添加引用',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 轻量虚线边框（RN borderStyle: 'dashed' 等价物，不引入第三方依赖）
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;

    void drawDash(Offset start, Offset end) {
      final total = (end - start).distance;
      var covered = 0.0;
      while (covered < total) {
        final next = (covered + dashWidth).clamp(0.0, total);
        canvas.drawLine(
          start + (end - start) * (covered / total),
          start + (end - start) * (next / total),
          paint,
        );
        covered = next + dashSpace;
      }
    }

    drawDash(Offset.zero, Offset(size.width, 0));
    drawDash(Offset(size.width, 0), Offset(size.width, size.height));
    drawDash(Offset(size.width, size.height), Offset.zero);
    drawDash(Offset.zero, Offset(0, size.height));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
