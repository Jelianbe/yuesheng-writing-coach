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

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../config/editor_background_presets.dart';
import '../../providers/writing_providers.dart';
import '../../widgets/paragraph_format_formatter.dart';
import '../../widgets/punctuation_bar.dart';
import 'smart_punctuation_formatter.dart';
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
    //
    // ★ 2026-09-22（批次 M5）：配色解析抽到 `_resolveColors` —— 本批新增
    //   `globalIsDark` 后 `build` 达 65 行（R-019 上限 50）。抽的是**独立方法 +
    //   显式参数**（真分解），与 `_buildEditorContainer` 同先例。
    final c = _resolveColors(context);
    return Column(
      children: [
        WritingOfflineBanner(isOffline: state.isOffline),
        Expanded(
          child: _buildEditorContainer(
            c.palette,
            c.titleColor,
            c.hintColor,
            c.dividerColor,
            c.globalIsDark,
          ),
        ),
        WritingSaveStatusBar(
          isSaving: state.isSaving,
          saveError: state.saveError,
          autosavePaused: state.autosavePaused,
          lastSavedAt: state.lastSavedAt,
          darkUi: c.darkUi,
        ),
        _buildPunctuationBar(c.palette, c.darkUi),
      ],
    );
  }

  /// 解析编辑器配色（纯计算，无副作用）。
  ///
  /// ★ 2026-09-22（批次 M5）从 `build` 抽出以回到 R-019 上限内。
  ///
  /// 配色来源与判据（三层，改动前请先读）：
  ///   · **三色**（正文 / hint / 底色）统一经 `editorXxxColorFor(key)` 取 ——
  ///     它们由**编辑器预设轴**决定，不吃全局 `context.palette`（R4 不变式）。
  ///   · **`globalIsDark`** = 全局主题是否暗（`Theme.of(context).brightness`）——
  ///     这是「跟随主题」预设的**唯一**外部输入。用 `Theme.of` 而非
  ///     `context.palette` 的色值，因为前者是主题的**权威声明**，
  ///     后者在预设轴语境下会被 `editorPaletteFor` 覆盖掉（易误读）。
  ///   · **`darkUi`** = 周边 UI（保存条 / 标点栏 / 分隔线）是否按暗底处理 ——
  ///     M5 起用 `isDarkEditorEffectiveFor`（key + 全局主题）而非
  ///     `isDarkEditorPreset`（只看 key），否则 `auto` 恒被判成亮底。
  _EditorColors _resolveColors(BuildContext context) {
    // 批次 M1 注：编辑器三色改由 **palette 驱动**。
    //   改造前直接调 `editorTextColorFor(key)`（内部读静态 `AppColors.*`），
    //   使编辑器预设轴游离于主题体系之外 —— 加第 N 套主题时这些色不会跟随。
    final palette = context.palette;
    final globalIsDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = editorTextColorFor(
      palette,
      state.editorBackground,
      globalIsDark: globalIsDark,
    );
    // 批次 V-3（P0-5）：占位提示色随预设联动。
    // 此前两处 hintStyle 硬编码 AppColors.textTertiary ⇒「暗夜」预设下
    // 提示对 editorDarkPanel 仅 2.79:1，几乎不可见。
    final hintColor = editorHintColorFor(
      palette,
      state.editorBackground,
      globalIsDark: globalIsDark,
    );
    final darkUi = isDarkEditorEffectiveFor(
      state.editorBackground,
      globalIsDark: globalIsDark,
    );
    // 分隔线：判据改用 **预设 key**（表现无关）而非**颜色值比较**。
    // 改造前为 `titleColor == AppColors.textPrimary` —— 依赖「颜色相等」推断
    // 「当前是否暗夜」，一旦 token 值调整（或加第三套主题）即静默失效。
    final dividerColor = darkUi
        ? palette.textTertiary.withValues(alpha: 0.25)
        : palette.divider;
    return _EditorColors(
      palette: palette,
      titleColor: titleColor,
      hintColor: hintColor,
      dividerColor: dividerColor,
      darkUi: darkUi,
      globalIsDark: globalIsDark,
    );
  }

  /// 编辑器整体容器（背景色铺满 + 标题块 + 分隔线 + 正文块）
  ///
  /// 批次 V-3 从 `build` 抽出：`build` 因新增 hint 联动已达 53 行（R-019 上限 50）。
  /// 抽的是**独立方法 + 显式参数**（真分解），不是 `part`/`extension` 伪拆分。
  Widget _buildEditorContainer(
    AppPalette palette,
    Color titleColor,
    Color hintColor,
    Color dividerColor,
    bool globalIsDark,
  ) {
    return Container(
      key: const Key('editorContainer'),
      color: editorBackgroundColorFor(
        palette,
        state.editorBackground,
        globalIsDark: globalIsDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTitleField(titleColor, hintColor),
          // 标题/正文分隔线（竹青细描边）
          Padding(
            // X-039-Batch1：20→section
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.section),
            child: Divider(height: 1, thickness: 0.6, color: dividerColor),
          ),
          Expanded(child: _buildContentArea(titleColor, hintColor)),
        ],
      ),
    );
  }

  /// ────────── 标题独立大块（批次90：大字号、独占空间、可聚焦光标）──────────
  Widget _buildTitleField(Color titleColor, Color hintColor) {
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
        // 方案A（边框溯源 ff7c61d4）：与正文一致，显式 disabled 全局兜底描边。
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: '未命名章节',
          hintStyle: TextStyle(
            fontSize: 28,
            height: 1.25,
            color: hintColor,
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
  Widget _buildContentArea(Color titleColor, Color hintColor) {
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
          // 编辑器性能-1（2026-09-21）：RepaintBoundary 隔离重绘——正文光标闪烁
          // （每 500ms）与内部滚动重绘只落在编辑器层，不再连带面包屑/保存状态条/
          // 标点栏整页重绘。
          RepaintBoundary(child: _buildContentField(titleColor, hintColor)),
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

  Widget _buildContentField(Color titleColor, Color hintColor) {
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
      // 方案A（边框溯源 ff7c61d4）：同上，显式 disabled 全局兜底描边。
      decoration: InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: '请输入正文内容',
        hintStyle: TextStyle(
          color: hintColor,
          fontSize: state.fontSize,
          height: state.lineSpacing,
        ),
      ),
      onChanged: onContentChanged,
    );
  }

  /// 底部标点栏（批次91-3：最前两位常驻撤销/重做；暗夜联动走 palette 令牌）
  ///
  /// ★ 2026-09-22（批次 M1）：三色由 `AppColors.editorDark*` 改为 `palette.*`。
  ///   两处取值**逐字节相同**（`AppPalette` 与 `AppColors` 本就重复定义同一组色），
  ///   故视觉零变化；改的是**来源**，使编辑器轴接入主题体系。
  Widget _buildPunctuationBar(AppPalette palette, bool darkUi) {
    return PunctuationBar(
      visibleIds: punctBarIds,
      // 批次88-5：自定义标点项
      customItems: punctCustomItems,
      onUndo: onUndo,
      onRedo: onRedo,
      backgroundColor: darkUi ? palette.editorDarkPanel : null,
      itemColor: darkUi ? palette.editorDarkText : null,
      actionColor: darkUi ? palette.editorDarkMuted : null,
      onTap: onPunctuationTap,
    );
  }
}

/// [_resolveColors] 的返回值 —— 编辑器一次 build 所需的全部配色决策。
///
/// 独立类而非 `record` / `Map`：字段含义需随代码留存（尤其 `globalIsDark`
/// 与 `darkUi` **语义不同**，命名相近最易误用 —— 前者是「全局主题是否暗」，
/// 后者是「编辑器周边 UI 是否按暗底渲染」，`auto` 预设下两者才相等）。
class _EditorColors {
  final AppPalette palette;
  final Color titleColor;
  final Color hintColor;
  final Color dividerColor;

  /// 编辑器周边 UI（保存状态条 / 标点栏 / 分隔线）是否按暗底渲染。
  final bool darkUi;

  /// 全局主题是否暗色 —— 「跟随主题」预设的解析输入。
  final bool globalIsDark;

  const _EditorColors({
    required this.palette,
    required this.titleColor,
    required this.hintColor,
    required this.dividerColor,
    required this.darkUi,
    required this.globalIsDark,
  });
}
