// ─────────────────────────────────────────────────────────────
// ChatInput — 聊天输入框（批次3：UI 入口按钮）
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
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class ChatInput extends StatefulWidget {
  final String input;
  final bool isStreaming;
  final ValueChanged<String> onInputChange;
  final ValueChanged<String> onSend;

  /// + 上传按钮回调（null 时不显示按钮）
  final VoidCallback? onUploadFile;

  /// @ 引用触发回调：用户输入 "@" 字符时调用（批次70：字符级触发）
  final VoidCallback? onMention;

  /// 停止生成回调（isStreaming 时由发送按钮位替换为停止按钮）
  final VoidCallback? onStop;

  /// 入口标识：'manuscript' 显示诊断模式占位符
  final String? entryPoint;

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
  });

  @override
  State<ChatInput> createState() => ChatInputState();
}

class ChatInputState extends State<ChatInput> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  /// 上一次文本（用于检测用户是否刚刚输入了 @ 字符）
  String _prevText = '';

  /// @ 触发的位置（offset），null 表示未触发
  int? _mentionAtOffset;

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
    super.dispose();
  }

  bool get _canSend =>
      _controller.text.trim().isNotEmpty && !widget.isStreaming;

  void _handleSend() {
    if (!_canSend) return;
    final text = _controller.text.trim();
    widget.onSend(text);
  }

  String get _placeholder => widget.entryPoint == 'manuscript'
      ? '描述你遇到的写作问题…输入 @ 引用作品'
      : '和月笙聊聊…输入 @ 引用作品';

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
  /// 注意：mentionPath 已由 buildMentionPath 带上 @ 前缀（如 "@W001/C003"），
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.borderSoft, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── + 上传按钮（secondary，带边框）──
          if (widget.onUploadFile != null) ...[
            _IconButton(
              icon: Icons.add,
              color: AppColors.textPrimary,
              onTap: widget.onUploadFile!,
              hasBorder: true,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !widget.isStreaming,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              onChanged: _handleChanged,
              decoration: InputDecoration(
                hintText: _placeholder,
                hintStyle: const TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  // pill shape：半径取大值，由引擎 clamp 到实际高度一半，
                  // 保证单行/多行均为完全圆角药丸形
                  borderRadius: BorderRadius.circular(100),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            height: 36,
            child: widget.isStreaming
                ? FilledButton(
                    // 生成/识别中：发送按钮位变为「停止生成」，给用户手动逃生出口
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
          ),
        ],
      ),
    );
  }
}

/// 输入框旁的 28x28 圆角图标按钮（对齐 RN INPUT_LAYOUT.iconButtonSize=28）
class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  /// true 时显示底色 + 边框（secondary 态，对应 + 按钮）
  final bool hasBorder;

  const _IconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.hasBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: hasBorder ? AppColors.surface : null,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: hasBorder
              ? Border.all(color: AppColors.borderSoft, width: 1)
              : null,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
