// ─────────────────────────────────────────────────────────────
// SessionDrawer — 会话管理抽屉
// 真源：yuesheng-android/src/components/chat/SessionDrawer.tsx
//
// 结构：头部「对话」+ 会话列表（头像/标题/时间/预览）+ 空态 CTA
// v30：每条右侧 ⋯ 浮层菜单（重命名/置顶/多选/删除）；长按也弹同一菜单；
//      多选模式可批量删除。置顶后会话排最前（pinned DESC, updatedAt DESC）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/repositories/session_repository.dart';
import '../utils/time_format.dart';

class SessionDrawer extends StatefulWidget {
  /// 会话列表（listSessionsWithPhase，pinned DESC, updatedAt DESC）
  final List<SessionWithPhase> sessions;

  /// 当前会话 ID（高亮显示）
  final String? currentSessionId;

  /// 选择会话（drawer 先关闭再回调）
  final ValueChanged<String> onSelect;

  /// 新建会话
  final VoidCallback onCreate;

  /// 删除单条会话（确认后关抽屉 → 回调）
  final ValueChanged<String>? onDelete;

  /// 重命名会话（v30）
  final void Function(String sessionId, String title)? onRename;

  /// 切换置顶（v30）
  final ValueChanged<String>? onTogglePin;

  /// 批量删除（v30 多选模式）
  final ValueChanged<List<String>>? onBatchDelete;

  const SessionDrawer({
    super.key,
    required this.sessions,
    required this.currentSessionId,
    required this.onSelect,
    required this.onCreate,
    this.onDelete,
    this.onRename,
    this.onTogglePin,
    this.onBatchDelete,
  });

  @override
  State<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<SessionDrawer> {
  bool _multiSelect = false;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surfaceWhite,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody(context)),
            if (_multiSelect) _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 14,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Row(
        children: [
          if (_multiSelect)
            TextButton(
              onPressed: _exitMultiSelect,
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textPrimary),
              ),
            )
          else
            const SizedBox(width: 48),
          const Expanded(
            child: Text(
              '对话',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _buildHeaderTrailing(),
        ],
      ),
    );
  }

  Widget _buildHeaderTrailing() {
    return SizedBox(
      width: 48,
      child: _multiSelect
          ? Text(
              '已选 ${_selected.length}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            )
          : IconButton(
              icon: const Icon(
                Icons.more_horiz,
                size: 22,
                color: AppColors.textSecondary,
              ),
              tooltip: '批量管理',
              onPressed: () => setState(() => _multiSelect = true),
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.sessions.isEmpty) return _buildEmpty(context);
    return ListView.separated(
      itemCount: widget.sessions.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.borderSoft),
      itemBuilder: (context, i) => _buildCard(context, widget.sessions[i]),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            size: 40,
            color: AppColors.disabledText,
          ),
          const SizedBox(height: 12),
          const Text(
            '还没有会话',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '发起你的第一次对话，开始写作诊断之旅',
            textAlign: TextAlign.center,
            style: AppTextStyles.subCaption,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onCreate();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: const Text('发起第一次对话'),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, SessionWithPhase item) {
    final id = item.session.id;
    final isActive = id == widget.currentSessionId;
    final title = item.session.title.isEmpty ? '新建会话' : item.session.title;
    final isPinned = item.session.pinned == 1;
    return GestureDetector(
      onLongPressStart: (details) =>
          _openMenu(context, item, title, details.globalPosition),
      child: InkWell(
        onTap: () => _onCardTap(id, isActive),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              if (_multiSelect) _buildSelectCheck(id),
              _buildAvatar(isActive),
              const SizedBox(width: 12),
              Expanded(child: _cardContent(item, title, isPinned)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectCheck(String id) {
    final checked = _selected.contains(id);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Icon(
        checked ? Icons.check_circle : Icons.circle_outlined,
        color: checked ? AppColors.primary : AppColors.disabledText,
        size: 22,
      ),
    );
  }

  Widget _buildAvatar(bool isActive) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppColors.surface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '月',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isActive ? AppColors.onPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _cardContent(SessionWithPhase item, String title, bool isPinned) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isPinned)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.push_pin, size: 13, color: AppColors.primary),
              ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatRelativeTime(item.session.updatedAt),
              style: AppTextStyles.microCaption,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          item.session.preview.isEmpty ? '暂无消息' : item.session.preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
        ),
      ],
    );
  }

  void _onCardTap(String id, bool isActive) {
    if (_multiSelect) {
      setState(() {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      });
      return;
    }
    Navigator.of(context).pop();
    widget.onSelect(id);
  }

  // ── 浮层菜单（对齐参考：重命名/置顶/多选/删除）──
  RelativeRect _menuPosition(BuildContext context, Offset globalPos) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      globalPos & const Size(40, 40),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    SessionWithPhase item,
    String title,
    Offset globalPos,
  ) async {
    final isPinned = item.session.pinned == 1;
    final result = await showMenu<String>(
      context: context,
      position: _menuPosition(context, globalPos),
      items: [
        _menuItem('rename', Icons.edit_outlined, '重命名'),
        _menuItem(
          'pin',
          isPinned ? Icons.push_pin_outlined : Icons.push_pin_outlined,
          isPinned ? '取消置顶' : '置顶',
        ),
        _menuItem('delete', Icons.delete_outline, '删除', danger: true),
      ],
    );
    if (!mounted || !context.mounted || result == null) return;
    switch (result) {
      case 'rename':
        _showRenameDialog(context, item.session.id, title);
      case 'pin':
        widget.onTogglePin?.call(item.session.id);
      case 'delete':
        _confirmDelete(context, item);
    }
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: danger ? AppColors.danger : AppColors.textPrimary,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: danger ? AppColors.danger : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── 重命名 ──
  Future<void> _showRenameDialog(
    BuildContext context,
    String id,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话', style: AppTextStyles.titleLg),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: '输入会话名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty && newTitle != current) {
      widget.onRename?.call(id, newTitle);
    }
  }

  // ── 删除单条（确认后关抽屉 → 回调）──
  Future<void> _confirmDelete(
    BuildContext context,
    SessionWithPhase item,
  ) async {
    final title = item.session.title.isEmpty ? '新建会话' : item.session.title;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: AppColors.overlay,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话', style: AppTextStyles.titleLg),
        content: Text(
          '删除「$title」？该会话的全部对话记录将一并删除，此操作不可撤销。',
          textAlign: TextAlign.center,
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '取消',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text(
              '删除',
              style: TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      widget.onDelete?.call(item.session.id);
    }
  }

  Widget _buildBottomBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSoft)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(
                () => _selected
                  ..clear()
                  ..addAll(widget.sessions.map((s) => s.session.id)),
              ),
              child: const Text(
                '全选',
                style: TextStyle(color: AppColors.textPrimary),
              ),
            ),
            FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => _confirmBatchDelete(context),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: Text(
                '删除 ${_selected.isEmpty ? '' : _selected.length}',
                style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBatchDelete(BuildContext context) async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除', style: AppTextStyles.titleLg),
        content: Text('删除选中的 $count 个会话？此操作不可撤销。', style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text(
              '删除',
              style: TextStyle(color: AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final ids = _selected.toList();
      _exitMultiSelect();
      Navigator.of(context).pop();
      widget.onBatchDelete?.call(ids);
    }
  }

  void _exitMultiSelect() {
    setState(() {
      _multiSelect = false;
      _selected.clear();
    });
  }
}
