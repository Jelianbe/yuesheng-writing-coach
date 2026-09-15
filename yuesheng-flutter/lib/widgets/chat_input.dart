// ─────────────────────────────────────────────────────────────
// ChatInput — 聊天输入栏（统一胶囊 + 「+」浮层面板）
// 复刻 yuesheng-android/src/components/chat/ChatInput.tsx
//
// 批次3 范围（对齐 RN ChatInput.tsx L48-82）：
//   - + 按钮（onUploadFile 回调，传了才显示）
//   - 多行 TextInput（1-5 行自适应）
//   - 圆形发送按钮（竹青主题）
//   - isStreaming 时禁用输入和发送（按钮不受影响，对齐 RN）
//
// 批次70：@ 功能合并进输入框
//   - 移除独立的 @ 图标按钮，改为输入 @ 字符触发引用选择器
//   - placeholder 提示「输入 @ 引用作品」
//   - 对外暴露 insertMention(mentionPath) 方法，在 @ 位置替换插入
//
// 2026-09-15（舰长真机反馈）：「+」左侧回归 + 思考开关入面板
//   - 「+」从输入框**右侧**移回**左侧**；发送按钮一并**纳入胶囊内部**，
//     三者（+ / 输入区 / 发送）同处一个圆角胶囊，不再是「胶囊 + 外挂按钮」；
//   - 原常驻于输入框上方的「思考」开关行**删除**，改为收进「+」面板
//     ⇒ 输入区上方不再额外占用一行垂直空间；
//   - 「+」点击不再直接弹覆盖式 bottom sheet，而是在「+」**正上方**
//     浮出一块小面板（上传作品 / 思考开关），点面板外任意处收起。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'chat_plus_panel.dart';

class ChatInput extends StatefulWidget {
  final String input;
  final bool isStreaming;
  final ValueChanged<String> onInputChange;
  final ValueChanged<String> onSend;

  /// + 面板内的「上传作品」回调（null 时该功能项不出现）。
  final VoidCallback? onUploadFile;

  /// @ 引用触发回调：用户输入 "@" 字符时调用（批次70：字符级触发）
  final VoidCallback? onMention;

  /// 停止生成回调（isStreaming 时由发送按钮位替换为停止按钮）
  final VoidCallback? onStop;

  /// 入口标识：'manuscript' 显示诊断模式占位符
  final String? entryPoint;

  /// 思考开关当前状态（true = 思考开启 ⇔ 档位非「关闭思考」）。
  final bool thinkingEnabled;

  /// 面板内的档位副文案（当前档位展示名；关闭态由面板改写为「已关闭」）。
  final String reasoningTierLabel;

  /// 思考开关回调（null 时**面板不渲染该功能项**，保证既有调用点零改动）。
  final ValueChanged<bool>? onThinkingToggle;

  const ChatInput({
    super.key,
    required this.input,
    required this.isStreaming,
    required this.onInputChange,
    required this.onSend,
    this.onUploadFile,
    this.onMention,
    this.onStop,
    this.entryPoint,
    this.thinkingEnabled = true,
    this.reasoningTierLabel = '标准',
    this.onThinkingToggle,
  });

  @override
  State<ChatInput> createState() => ChatInputState();
}

class ChatInputState extends State<ChatInput> {
  /// 面板高度保守估计（**仅**用于「上方空间不足」时的钳制，非布局依据；
  /// 真实高度随功能项增删变化，故定位用 bottom 锚定，不依赖此值）。
  static const double _kPanelEstimatedHeight = 132;

  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  /// 输入框纵向滚动控制器（内容超 maxLines 时框内滚动 + 滑块指示）
  final ScrollController _scrollController = ScrollController();

  /// 上一次文本（用于检测用户是否刚刚输入了 @ 字符）
  String _prevText = '';

  /// @ 触发的位置（offset），null 表示未触发
  int? _mentionAtOffset;

  /// 「+」按钮锚点：面板落点由它的全局坐标算出。
  final GlobalKey _plusKey = GlobalKey();

  /// 「+」面板浮层控制器（OverlayPortal 自带生命周期，无需手动 remove）
  final OverlayPortalController _panelController = OverlayPortalController();

  /// 面板与「+」按钮共用的 TapRegion 组：组内点击不收面板，组外点击收。
  final Object _panelGroup = Object();

  /// 面板左边缘 / 底边（overlay 坐标系）。打开前由 _updatePanelAnchor 刷新。
  double _panelLeft = 0;
  double _panelBottom = 0;

  /// 批次81：聚焦输入框（三卡「返回对话/继续对话/补充内容」复用，
  /// 让用户点击后直接接着对话）
  void focusInput() {
    _focusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.input);
    _prevText = widget.input;
  }

  @override
  void didUpdateWidget(ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.input != widget.input && _controller.text != widget.input) {
      _controller.text = widget.input;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _prevText = widget.input;
    }
    if (oldWidget.isStreaming != widget.isStreaming) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _controller.text.trim().isNotEmpty && !widget.isStreaming;

  /// 面板是否有内容 ⇒ 决定「+」是否出现。
  /// 上传或思考开关任一存在就必须有入口，否则该功能不可达。
  bool get _hasPanel =>
      widget.onUploadFile != null || widget.onThinkingToggle != null;

  void _handleSend() {
    if (!_canSend) return;
    final text = _controller.text.trim();
    widget.onSend(text);
  }

  String get _placeholder =>
      widget.entryPoint == 'manuscript' ? '描述你遇到的写作问题…输入 @ 引用作品' : '输入 @ 引用作品';

  /// 检测用户是否刚刚输入了 "@" 字符
  /// 返回 true 时表示触发引用选择器
  bool _detectMentionTriggered(String newText) {
    if (widget.onMention == null) return false;

    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;

    final cursor = selection.baseOffset;
    // 光标前一位必须是 "@"
    if (cursor < 1 || newText.length < cursor) return false;
    if (newText[cursor - 1] != '@') return false;

    // 新增字符判断：新文本比旧文本多一个字符，且插入位置就是 "@"
    // （避免用户删除、粘贴、移动光标等场景误触发）
    final addedOneChar = newText.length == _prevText.length + 1;
    if (!addedOneChar) return false;

    // 记录 @ 的位置（cursor - 1），稍后替换
    _mentionAtOffset = cursor - 1;
    return true;
  }

  void _handleChanged(String newText) {
    final mentionTriggered = _detectMentionTriggered(newText);
    _prevText = newText;
    widget.onInputChange(newText);
    if (mentionTriggered) {
      widget.onMention?.call();
    }
  }

  /// 在 @ 触发位置替换插入 mentionPath
  /// 注意：mentionPath 已由 buildMentionPath 带上 @ 前缀（如 "@AAA/第一章"），
  /// 这里不再重复加 @。（批次70：替代原来简单拼接在末尾的方式）
  void insertMention(String mentionPath) {
    final at = _mentionAtOffset;
    if (at == null) {
      // 没检测到 @ 触发（比如直接点击了选择器入口），退化为末尾追加
      final current = _controller.text;
      final space = current.isEmpty || current.endsWith(' ') ? '' : ' ';
      final newText = '$current$space$mentionPath ';
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: newText.length);
      _prevText = newText;
      widget.onInputChange(newText);
      return;
    }

    // 在 at 位置把用户刚输入的 "@" 替换为 "$mentionPath "
    // （mentionPath 本身以 @ 开头，所以等价于把 "@" 扩展成完整引用）
    final text = _controller.text;
    final insertStr = '$mentionPath ';
    final newText = text.replaceRange(at, at + 1, insertStr);
    _controller.text = newText;
    final cursor = at + insertStr.length;
    _controller.selection = TextSelection.collapsed(
      offset: cursor.clamp(0, newText.length),
    );
    _prevText = newText;
    _mentionAtOffset = null;
    widget.onInputChange(newText);
  }

  /// 开合「+」面板：已在显示则收起，否则先刷新落点再展开。
  void _togglePanel() {
    if (_panelController.isShowing) {
      _panelController.hide();
      return;
    }
    _updatePanelAnchor();
    _panelController.show();
  }

  /// 计算面板落点：「+」正上方 8px，左边缘与「+」对齐并钳制在屏内。
  /// 用 bottom 而非 top 定位 ⇒ 无需预知面板高度（内容可增删）。
  void _updatePanelAnchor() {
    final box = _plusKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(context).size;
    final maxLeft = (screen.width - ChatPlusPanel.width - AppSpacing.md)
        .clamp(AppSpacing.md, double.infinity)
        .toDouble();
    _panelLeft = origin.dx.clamp(AppSpacing.md, maxLeft).toDouble();
    // 底边距 overlay 底边 = 屏高 −「+」顶边 + 8 ⇒ 面板正悬在「+」上方。
    // sanity：上方空间不足（横屏 / 输入法挤压）时宁可贴顶，
    // 也不可把面板顶出屏外变成不可见不可点。
    final topLimit = screen.height - AppSpacing.md - _kPanelEstimatedHeight;
    _panelBottom = (screen.height - origin.dy + AppSpacing.sm)
        .clamp(0.0, topLimit < 0 ? 0.0 : topLimit)
        .toDouble();
  }

  /// 「上传作品」项：先收面板再交给宿主（避免两层浮层叠在一起）。
  void _handleUploadTap() {
    _panelController.hide();
    widget.onUploadFile?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        // X-039-Batch1：16→lg / 8→sm / 16→lg（+MediaQuery bottom 动态，不令牌）
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.borderSoft, width: 0.5),
        ),
      ),
      child: OverlayPortal(
        controller: _panelController,
        overlayChildBuilder: _buildPanelOverlay,
        child: _buildCapsule(),
      ),
    );
  }

  /// 输入胶囊：+ / 输入区 / 发送 同处一个圆角容器（2026-09-15 版式）
  Widget _buildCapsule() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_hasPanel) _buildPlusButton(),
          Expanded(child: _buildTextField()),
          _buildSendButton(),
        ],
      ),
    );
  }

  /// 左侧「+」：开合功能面板（面板本体由 OverlayPortal 渲染）
  Widget _buildPlusButton() {
    return TapRegion(
      groupId: _panelGroup,
      child: InkWell(
        key: _plusKey,
        onTap: _togglePanel,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(Icons.add, size: 20, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  /// 胶囊内的输入区：无自有底色/边框（底色由胶囊提供）
  Widget _buildTextField() {
    return Scrollbar(
      controller: _scrollController,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        scrollController: _scrollController,
        enabled: !widget.isStreaming,
        maxLines: 5,
        minLines: 1,
        textInputAction: TextInputAction.newline,
        onChanged: _handleChanged,
        decoration: InputDecoration(
          hintText: _placeholder,
          hintStyle: const TextStyle(color: AppColors.textTertiary),
          filled: false,
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            // vertical 撑到与 + / 发送按钮（40）齐高 ⇒ 单行三件同高
            vertical: AppSpacing.smx,
          ),
        ),
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
    );
  }

  /// 右侧发送位：生成中变「停止生成」，给用户手动逃生出口
  Widget _buildSendButton() {
    return SizedBox(
      width: 40,
      height: 40,
      child: widget.isStreaming
          ? FilledButton(
              onPressed: widget.onStop,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(
                Icons.stop,
                color: AppColors.onPrimary,
                size: 18,
              ),
            )
          : FilledButton(
              onPressed: _canSend ? _handleSend : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.disabled,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(
                Icons.arrow_upward,
                color: AppColors.onPrimary,
                size: 18,
              ),
            ),
    );
  }

  /// 「+」上方的浮层面板；点击面板外任意处收起。
  Widget _buildPanelOverlay(BuildContext context) {
    return Positioned(
      left: _panelLeft,
      bottom: _panelBottom,
      child: TapRegion(
        groupId: _panelGroup,
        onTapOutside: (_) => _panelController.hide(),
        child: ChatPlusPanel(
          onUpload: widget.onUploadFile == null ? null : _handleUploadTap,
          thinkingEnabled: widget.thinkingEnabled,
          reasoningTierLabel: widget.reasoningTierLabel,
          onThinkingToggle: widget.onThinkingToggle,
          isStreaming: widget.isStreaming,
        ),
      ),
    );
  }
}
