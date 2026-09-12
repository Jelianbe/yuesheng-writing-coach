// ─────────────────────────────────────────────────────────────
// writing_page 视图层：编辑器主体（离线横幅 / 标题 / 正文 / 划词菜单 /
// 保存状态条 / 标点栏）
//
// 由 C92-6a 伪拆分清偿自 writing_page.dart 提取为独立 StatelessWidget
// （R-019：独立类 / 显式接口，非 part 伪拆分）。
// 行为与原实现逐字等价：Key（`editorContainer` / `chapterTitleField` /
// `chapterContentField`）/ 字号 / 间距令牌 / 文案 / 输入格式器零变化。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../config/editor_background_presets.dart';
import '../../../providers/writing_providers.dart';
import '../../paragraph_format_formatter.dart';
import '../../punctuation_bar.dart';
import '../../smart_punctuation_formatter.dart';
import 'writing_page_chrome.dart';
import 'writing_status_views.dart';

/// 写作页编辑器主体（标题独立大块 + 正文独立大块 + 底部标点栏）
class WritingEditorView extends StatelessWidget {
  const WritingEditorView({
    super.key,
    required this.state,
    required this.titleController,
    required this.contentController,
    required this.focusNode,
    required this.editorStackKey,
    required this.punctBarIds,
    required this.punctCustomItems,
    required this.showSelectionMenu,
    required this.selectionMenuPos,
    required this.onTitleChanged,
    required this.onContentChanged,
    required this.onDiagnoseSelection,
    required this.onUndo,
    required this.onRedo,
    required this.onPunctuationTap,
  });

  final WritingState state;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final FocusNode focusNode;

  /// 正文编辑区 Stack 的 GlobalKey（划词菜单位置反查用，需与宿主共用同一实例）
  final GlobalKey editorStackKey;

  final List<String>? punctBarIds;
  final List<PunctuationItem> punctCustomItems;

  /// 划词菜单可见性 + 相对正文 Stack 的位置（null = 不可定位 → 保持隐藏）
  final bool showSelectionMenu;
  final Offset? selectionMenuPos;

  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onContentChanged;
  final VoidCallback onDiagnoseSelection;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final ValueChanged<String> onPunctuationTap;

  @override
  Widget build(BuildContext context) {
    // 批次82 P0-④：面板改为右侧侧栏，正文不被覆盖 → 标点栏不再随面板隐藏
    // 批次90：标题/正文完全独立（用户参考图要求：标题独立大区块 + 正文分开）
    final titleColor = editorTextColorFor(state.editorBackground);
    final dividerColor = (titleColor == AppColors.textPrimary)
        ? AppColors.divider
        : AppColors.textTertiary.withValues(alpha: 0.25);
    final darkUi = isDarkEditorPreset(state.editorBackground);

    return Column(
      children: [
        WritingOfflineBanner(isOffline: state.isOffline),
        Expanded(
          // 编辑器整体容器：背景色铺满
          child: Container(
            key: const Key('editorContainer'),
            color: editorBackgroundColorFor(state.editorBackground),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTitleField(titleColor),
                // 标题/正文分隔线（竹青细描边）
                Padding(
                  // X-039-Batch1：20→section
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.section,
                  ),
                  child: Divider(
                    height: 1,
                    thickness: 0.6,
                    color: dividerColor,
                  ),
                ),
                Expanded(child: _buildContentArea(titleColor)),
              ],
            ),
          ),
        ),
        WritingSaveStatusBar(
          isSaving: state.isSaving,
          saveError: state.saveError,
          autosavePaused: state.autosavePaused,
          lastSavedAt: state.lastSavedAt,
          darkUi: darkUi,
        ),
        _buildPunctuationBar(darkUi),
      ],
    );
  }

  /// ────────── 标题独立大块（批次90：大字号、独占空间、可聚焦光标）──────────
  Widget _buildTitleField(Color titleColor) {
    return Padding(
      // X-039-Batch1：20→section / 28（非标准= section+sm / 16→lg）— 28 为标题专属
      // 垂直大间距，保留字面（无法映射），后续如需令牌化单独补 largeV=28
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.section + AppSpacing.sm,
        AppSpacing.section,
        AppSpacing.lg,
      ),
      child: TextField(
        key: const Key('chapterTitleField'),
        controller: titleController,
        // 输入即保存（对齐 RN handleTitleChange）
        style: TextStyle(
          fontSize: 28,
          height: 1.25,
          color: titleColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
        decoration: InputDecoration.collapsed(
          hintText: '未命名章节',
          hintStyle: TextStyle(
            fontSize: 28,
            height: 1.25,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w800,
          ),
        ),
        textInputAction: TextInputAction.next,
        // 批次95-3：键盘「下一项」→ 聚焦正文（标配）
        onSubmitted: (_) => focusNode.requestFocus(),
        maxLines: 1,
        onChanged: onTitleChanged,
      ),
    );
  }

  /// ────────── 正文独立大块 ──────────
  Widget _buildContentArea(Color titleColor) {
    return Padding(
      // X-039-Batch1：20→section / 16→lg
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.lg,
        AppSpacing.section,
        AppSpacing.lg,
      ),
      child: Stack(
        key: editorStackKey, // 批次95-1：划词菜单位置反查用
        children: [
          _buildContentField(titleColor),
          // B3 划词诊断：浮动菜单跟随选区（批次95-1：RenderEditable 定位 + 屏幕外翻转）
          if (showSelectionMenu && selectionMenuPos != null)
            WritingSelectionMenu(
              position: selectionMenuPos!,
              onDiagnose: onDiagnoseSelection,
            ),
        ],
      ),
    );
  }

  Widget _buildContentField(Color titleColor) {
    return TextField(
      key: const Key('chapterContentField'),
      controller: contentController,
      focusNode: focusNode,
      maxLines: null,
      // 批次85-6：智能标点（左配对符自动补右符 + 右符前输入自动跳过）
      // 批次88-4：段落格式（回车自动补缩进 / 段间空行，随排版设置开关）
      inputFormatters: [
        if (state.smartPunctOn) const SmartPunctuationFormatter(),
        ParagraphFormatFormatter(
          indentOn: state.indentParagraph,
          blankLineOn: state.blankLineBetween,
        ),
      ],
      style: TextStyle(
        fontSize: state.fontSize,
        height: state.lineSpacing,
        color: titleColor,
      ),
      decoration: InputDecoration.collapsed(
        hintText: '请输入正文内容',
        hintStyle: TextStyle(
          color: AppColors.textTertiary,
          fontSize: state.fontSize,
          height: state.lineSpacing,
        ),
        border: InputBorder.none,
      ),
      onChanged: onContentChanged,
    );
  }

  /// 底部标点栏（批次91-3：最前两位常驻撤销/重做；暗夜联动走 AppColors 令牌）
  Widget _buildPunctuationBar(bool darkUi) {
    return PunctuationBar(
      visibleIds: punctBarIds,
      // 批次88-5：自定义标点项
      customItems: punctCustomItems,
      onUndo: onUndo,
      onRedo: onRedo,
      backgroundColor: darkUi ? AppColors.editorDarkPanel : null,
      itemColor: darkUi ? AppColors.editorDarkText : null,
      actionColor: darkUi ? AppColors.editorDarkMuted : null,
      onTap: onPunctuationTap,
    );
  }
}
