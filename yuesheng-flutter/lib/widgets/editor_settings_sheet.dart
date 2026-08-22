// ─────────────────────────────────────────────────────────────
// EditorSettingsSheet — 排版设置弹层（批次82 P0 四件套之①）
//
// 真人创作第一刚需：字号 / 行距 / 背景色（护眼）。
// 入口：写作页 ⋮ 更多菜单 →「排版设置」。
//
// 交互：
//   - 字号/行距滑条：拖动即时预览（写 WritingStore 内存态），松手持久化
//   - 背景预设：点选即时生效 + 持久化
//   - 设置用户级持久化（app_state，跨章节生效），重启保留
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/app_state_repository.dart';
import '../providers/app_providers.dart';
import '../providers/writing_providers.dart';
import 'punctuation_bar.dart';
import 'yue_sheet.dart';

/// 背景预设（key 与 WritingState.editorBackground 对应）
class EditorBackgroundPreset {
  final String key;
  final String label;
  final Color color;
  final Color textColor;
  const EditorBackgroundPreset({
    required this.key,
    required this.label,
    required this.color,
    required this.textColor,
  });
}

/// 编辑器背景预设列表（批次82）
const List<EditorBackgroundPreset> editorBackgroundPresets = [
  EditorBackgroundPreset(
    key: editorBgPaper,
    label: '米纸',
    color: Color(0xFFF5F1E8),
    textColor: Color(0xFF1A1A1A),
  ),
  EditorBackgroundPreset(
    key: editorBgWarm,
    label: '暖白',
    color: Color(0xFFFFFBF0),
    textColor: Color(0xFF1A1A1A),
  ),
  EditorBackgroundPreset(
    key: editorBgGreen,
    label: '护眼',
    color: Color(0xFFE6F0E9),
    textColor: Color(0xFF1A1A1A),
  ),
  EditorBackgroundPreset(
    key: editorBgDark,
    label: '暗夜',
    color: Color(0xFF26282B),
    textColor: Color(0xFFE8EAED),
  ),
];

/// key → 预设（未命中回退米纸）
EditorBackgroundPreset editorBackgroundPresetOf(String key) {
  for (final preset in editorBackgroundPresets) {
    if (preset.key == key) return preset;
  }
  return editorBackgroundPresets.first;
}

/// 编辑器背景色（供 WritingPage 渲染正文底）
Color editorBackgroundColorFor(String key) =>
    editorBackgroundPresetOf(key).color;

/// 编辑器文字色（暗夜背景用浅色，其余墨色）
Color editorTextColorFor(String key) => editorBackgroundPresetOf(key).textColor;

/// 批次94-4：是否为暗夜背景预设（写作页周边 UI 取反联动判断）
bool isDarkEditorPreset(String key) => key == editorBgDark;

class EditorSettingsSheet extends ConsumerWidget {
  final String chapterId;

  /// 批次88-2：恢复对话按钮到右下角默认位置（由 WritingPage 注入）
  final VoidCallback? onResetFabPosition;

  /// 批次88-4：把当前段落格式批量应用到全文（按开关状态补/移除缩进、加/去空行）
  final void Function(bool applyIndent, bool applyBlankLine)?
  onApplyParagraphFormat;

  const EditorSettingsSheet({
    super.key,
    required this.chapterId,
    this.onResetFabPosition,
    this.onApplyParagraphFormat,
  });

  /// 打开排版设置弹层（批次82）
  static Future<void> show(
    BuildContext context, {
    required String chapterId,
    VoidCallback? onResetFabPosition,
    void Function(bool applyIndent, bool applyBlankLine)?
    onApplyParagraphFormat,
  }) {
    return showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => EditorSettingsSheet(
        chapterId: chapterId,
        onResetFabPosition: onResetFabPosition,
        onApplyParagraphFormat: onApplyParagraphFormat,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(writingStoreProvider(chapterId).notifier);
    final state = ref.watch(writingStoreProvider(chapterId));

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '排版设置',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildSliderRow(
              label: '字号',
              value: state.fontSize,
              min: 14,
              max: 24,
              divisions: 10,
              display: '${state.fontSize.round()}',
              onChanged: store.setFontSize,
              onChangeEnd: (_) => store.persistEditorSettings(),
            ),
            const SizedBox(height: 6),
            _buildSliderRow(
              label: '行距',
              value: state.lineSpacing,
              min: 1.2,
              max: 2.0,
              divisions: 8,
              display: state.lineSpacing.toStringAsFixed(1),
              onChanged: store.setLineSpacing,
              onChangeEnd: (_) => store.persistEditorSettings(),
            ),
            const SizedBox(height: 14),
            const Text(
              '背景',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final preset in editorBackgroundPresets) ...[
                  _BackgroundOption(
                    preset: preset,
                    selected: state.editorBackground == preset.key,
                    onTap: () {
                      store.setEditorBackground(preset.key);
                      store.persistEditorSettings();
                    },
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 14),
            // 批次88-4：段落格式——自动首行缩进 / 段间空行（开关即时生效 + 全文批量应用）
            _buildParagraphSection(store, state),
            const SizedBox(height: 14),
            // 批次96-9：三个开关从 ⋮ 菜单移入排版设置（reactive SwitchListTile）
            _buildTogglesSection(store, state),
            const SizedBox(height: 14),
            // 批次86-2：自定义工具栏——标点栏隐藏/排序
            const _PunctuationBarConfigSection(),
            // 批次88-2：对话按钮可见性开关 + 位置恢复（批次96-9：开关从菜单移入）
            const SizedBox(height: 14),
            _buildFabSection(store, state),
          ],
        ),
      ),
    );
  }

  /// 批次96-9：三个开关从 ⋮ 菜单移入排版设置——行段聚焦 / 智能标点
  /// （reactive SwitchListTile，store setter 即时生效 + persistEditorSettings 落库）
  Widget _buildTogglesSection(WritingStore store, WritingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '辅助',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '行段聚焦',
            style: TextStyle(fontSize: 14, color: AppColors.textInk),
          ),
          subtitle: const Text(
            '淡化当前段以外的内容，专注当前行段',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          value: state.focusMode,
          activeTrackColor: AppColors.primary,
          onChanged: (v) {
            store.setFocusMode(v);
            store.persistEditorSettings();
          },
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '智能标点',
            style: TextStyle(fontSize: 14, color: AppColors.textInk),
          ),
          subtitle: const Text(
            '输入「自动补全对应右符',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          value: state.smartPunctOn,
          activeTrackColor: AppColors.primary,
          onChanged: (v) {
            store.setSmartPunctOn(v);
            store.persistEditorSettings();
          },
        ),
      ],
    );
  }

  /// 批次96-9：对话按钮可见性开关 + 位置恢复（开关从菜单移入，位置恢复沿用原有入口）
  Widget _buildFabSection(WritingStore store, WritingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '对话按钮',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '显示对话按钮',
            style: TextStyle(fontSize: 14, color: AppColors.textInk),
          ),
          subtitle: const Text(
            '底部悬浮的 AI 对话入口，长按可拖动位置',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          value: state.fabVisible,
          activeTrackColor: AppColors.primary,
          onChanged: (v) {
            store.setFabVisible(v);
            store.persistEditorSettings();
          },
        ),
        if (onResetFabPosition != null)
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: onResetFabPosition,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('恢复右下角位置', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
      ],
    );
  }

  /// 批次88-4：段落格式节——两个开关 + 「应用到全文」批量按钮
  Widget _buildParagraphSection(WritingStore store, WritingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '段落',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onApplyParagraphFormat == null
                  ? null
                  : () => onApplyParagraphFormat!(
                      state.indentParagraph,
                      state.blankLineBetween,
                    ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('应用到全文', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '自动首行缩进',
            style: TextStyle(fontSize: 14, color: AppColors.textInk),
          ),
          subtitle: const Text(
            '回车换行时自动补两格缩进',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          value: state.indentParagraph,
          activeTrackColor: AppColors.primary,
          onChanged: (v) {
            store.setIndentParagraph(v);
            store.persistEditorSettings();
          },
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '段间空行',
            style: TextStyle(fontSize: 14, color: AppColors.textInk),
          ),
          subtitle: const Text(
            '段落之间留出空行',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          value: state.blankLineBetween,
          activeTrackColor: AppColors.primary,
          onChanged: (v) {
            store.setBlankLineBetween(v);
            store.persistEditorSettings();
          },
        ),
      ],
    );
  }

  /// 滑条行：label + 当前值 + Slider
  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.surface,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.12),
              trackHeight: 2,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

/// 背景预设圆点选项（选中显示描边 + label）
class _BackgroundOption extends StatelessWidget {
  final EditorBackgroundPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _BackgroundOption({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: preset.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2.5 : 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            preset.label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? AppColors.primary : AppColors.textTertiary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// 标点栏配置节（批次86-2 自定义工具栏）
/// 已启用标点按顺序展示，可上移/下移/隐藏；已隐藏可恢复。
/// 变更即写 app_state（punctuation_bar_config，即时保存）。
class _PunctuationBarConfigSection extends ConsumerStatefulWidget {
  const _PunctuationBarConfigSection();

  @override
  ConsumerState<_PunctuationBarConfigSection> createState() =>
      _PunctuationBarConfigSectionState();
}

class _PunctuationBarConfigSectionState
    extends ConsumerState<_PunctuationBarConfigSection> {
  /// null = 未配置（用默认全部）
  List<String>? _visibleIds;

  /// 批次88-5：自定义标点项（增删）
  List<PunctuationItem> _customItems = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    final ids = await repo.getPunctuationBarConfig();
    final customs = await repo.getPunctuationCustomItems();
    if (!mounted) return;
    setState(() {
      _visibleIds = ids;
      _customItems = customs;
    });
  }

  Future<void> _save(List<String> ids) async {
    await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).setPunctuationBarConfig(ids);
    if (!mounted) return;
    setState(() => _visibleIds = ids);
  }

  Future<void> _saveCustom(List<PunctuationItem> items) async {
    await AppStateRepository(
      ref.read(appDatabaseProvider),
    ).setPunctuationCustomItems(items);
    if (!mounted) return;
    setState(() => _customItems = items);
  }

  void _hide(String id) {
    final visible = _visibleIds ?? defaultPunctuationIds;
    _save([
      for (final v in visible)
        if (v != id) v,
    ]);
  }

  void _restore(String id) {
    final visible = _visibleIds ?? defaultPunctuationIds;
    _save([...visible, id]);
  }

  void _move(String id, int delta) {
    final visible = List.of(_visibleIds ?? defaultPunctuationIds);
    final i = visible.indexOf(id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= visible.length) return;
    final tmp = visible[i];
    visible[i] = visible[j];
    visible[j] = tmp;
    _save(visible);
  }

  /// 批次87-1 + 88-5：一键还原默认（清掉自定义项 + 重置顺序）
  void _resetToDefault() {
    _save(defaultPunctuationIds);
    _saveCustom(const []);
  }

  /// 批次88-5：添加自定义标点（弹输入框；去重；追加到可见列表末尾）
  Future<void> _promptAdd() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加常用标点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(hintText: '输入标点或短语，如 「」、『』'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (input == null) return;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    // 去重（内置 + 已添加的自定义）
    final exists =
        punctuationItems.any((it) => it.display == trimmed) ||
        _customItems.any((it) => it.display == trimmed);
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('这个标点已经在工具栏里了'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    final nextId =
        'custom_${(_customItems.length + 1).toString().padLeft(2, '0')}';
    await _saveCustom([
      ..._customItems,
      PunctuationItem(nextId, trimmed, trimmed),
    ]);
    final visible = _visibleIds ?? defaultPunctuationIds;
    await _save([...visible, nextId]);
  }

  /// 批次88-5：删除自定义标点（同时从可见列表移除）
  Future<void> _deleteCustom(String id) async {
    await _saveCustom([
      for (final it in _customItems)
        if (it.id != id) it,
    ]);
    final visible = _visibleIds ?? defaultPunctuationIds;
    await _save([
      for (final v in visible)
        if (v != id) v,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleIds ?? defaultPunctuationIds;
    final byId = {
      for (final it in punctuationItems) it.id: it,
      for (final it in _customItems) it.id: it,
    };
    final hidden = [
      for (final it in punctuationItems)
        if (!visible.contains(it.id)) it,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '标点栏',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            // 批次88-5：添加自定义标点（主操作）
            TextButton.icon(
              onPressed: _promptAdd,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加标点', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: _resetToDefault,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '隐藏不常用的，把常用的排在前面；也可以添加自己的常用标点',
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < visible.length; i++)
          _ConfigRow(
            item: byId[visible[i]]!,
            visible: true,
            canMoveUp: i > 0,
            canMoveDown: i < visible.length - 1,
            // 批次88-5：自定义项可删除，内置项只可隐藏
            isCustom: _customItems.any((it) => it.id == visible[i]),
            onHide: () => _hide(visible[i]),
            onDelete: () => _deleteCustom(visible[i]),
            onMoveUp: () => _move(visible[i], -1),
            onMoveDown: () => _move(visible[i], 1),
          ),
        if (hidden.isNotEmpty) ...[
          const Divider(height: 16),
          const Text(
            '已隐藏',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          for (final it in hidden)
            _ConfigRow(
              item: it,
              visible: false,
              canMoveUp: false,
              canMoveDown: false,
              onHide: () {},
              onDelete: () {},
              onMoveUp: () {},
              onMoveDown: () {},
              onRestore: () => _restore(it.id),
            ),
        ],
      ],
    );
  }
}

/// 标点栏配置行：显示标点 + （可见：上移/下移/隐藏或删除 | 隐藏：恢复）
class _ConfigRow extends StatelessWidget {
  final PunctuationItem item;
  final bool visible;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onHide;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback? onRestore;

  /// 批次88-5：是否为自定义项（自定义项显示「删除」，内置项显示「隐藏」）
  final bool isCustom;

  const _ConfigRow({
    required this.item,
    required this.visible,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onHide,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    this.onRestore,
    this.isCustom = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            item.display,
            style: const TextStyle(fontSize: 16, color: AppColors.textInk),
          ),
        ),
        const Spacer(),
        if (visible) ...[
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            color: canMoveUp ? AppColors.textSecondary : AppColors.disabledText,
            visualDensity: VisualDensity.compact,
            onPressed: canMoveUp ? onMoveUp : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 16),
            color: canMoveDown
                ? AppColors.textSecondary
                : AppColors.disabledText,
            visualDensity: VisualDensity.compact,
            onPressed: canMoveDown ? onMoveDown : null,
          ),
          if (isCustom)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              color: AppColors.warning,
              visualDensity: VisualDensity.compact,
              tooltip: '删除',
              onPressed: onDelete,
            )
          else
            TextButton(
              onPressed: onHide,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textTertiary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('隐藏', style: TextStyle(fontSize: 12)),
            ),
        ] else
          TextButton(
            onPressed: onRestore,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('恢复', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
