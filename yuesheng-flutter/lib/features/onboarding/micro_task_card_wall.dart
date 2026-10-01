// ─────────────────────────────────────────────────────────────
// micro_task_card_wall — 小白冷启动试点（ADR-C121）· 30 秒微任务卡片墙
//
// 位置：onboarding 完成后自动弹出 + 聊天页常驻入口（头部「写第一句」）。
// 流程：三张卡（叙述/对话/描写，对齐 N0 三激发）→ 选卡 → 写 50–200 字
//   → 提交（门槛 ≥50 字，与可诊断标准一致）→ 文本进会话自动走既有诊断链。
//
// 文案与数据真源：lib/services/onboarding_flow.dart（kMicroTaskCards）。
// R-009：只给任务约束（范围/字数/句式钩子），不替写句子、不给范文。
// 本文件全部是 UI 层新文案，不触注入 prompt（R-027 零触）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_palette.dart';
import '../../services/onboarding_flow.dart';
import '../../widgets/yue_sheet.dart';

/// 打开微任务卡片墙（底部弹层）。
///
/// [entry] 记录入口来源（auto/header/welcome），由调用方写入埋点
/// `card_wall_entered` 的 payload。
/// [onSubmit] 收到学员产出文本与卡 id；由调用方写入埋点并发送进会话。
Future<void> showMicroTaskWallSheet(
  BuildContext context, {
  required String entry,
  required void Function(String text, String cardId) onSubmit,
}) {
  return showYueModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) =>
        _MicroTaskWallContent(entry: entry, onSubmit: onSubmit),
  );
}

/// 卡片墙内容（列表 ⇄ 填写双态）
class _MicroTaskWallContent extends StatefulWidget {
  final String entry;
  final void Function(String text, String cardId) onSubmit;

  const _MicroTaskWallContent({required this.entry, required this.onSubmit});

  @override
  State<_MicroTaskWallContent> createState() => _MicroTaskWallContentState();
}

class _MicroTaskWallContentState extends State<_MicroTaskWallContent> {
  MicroTaskCard? _card;
  int _variantIndex = 0;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pickCard(MicroTaskCard card) {
    setState(() {
      _card = card;
      _variantIndex = 0;
    });
  }

  void _swapVariant() {
    setState(() {
      _variantIndex = (_variantIndex + 1) % (1 + (_card?.variants.length ?? 1));
    });
  }

  void _backToList() => setState(() => _card = null);

  void _submit() {
    final text = _controller.text.trim();
    if (text.length < kMicroTaskMinChars || _card == null) return;
    widget.onSubmit(text, _card!.id);
    Navigator.of(context).pop();
  }

  String get _promptText {
    final card = _card;
    if (card == null) return '';
    final total = 1 + card.variants.length;
    if (total == 1 || _variantIndex == 0) return card.prompt;
    return card.variants[_variantIndex - 1];
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: card == null ? _buildWall(context) : _buildFill(context, card),
      ),
    );
  }

  /// 列表态：标题 + 副题 + 三张卡 + 声明
  Widget _buildWall(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '写第一句 · 30 秒微任务',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kMicroTaskWallSubtitle,
            style: TextStyle(fontSize: 14, color: palette.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final card in kMicroTaskCards) ...[
            _WallCard(card: card, onTap: () => _pickCard(card)),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            kMicroTaskDisclaimer,
            style: TextStyle(fontSize: 12, color: palette.textTertiary),
          ),
        ],
      ),
    );
  }

  /// 填写态：任务约束 + 输入 + 换一个 + 提交
  Widget _buildFill(BuildContext context, MicroTaskCard card) {
    final palette = context.palette;
    final text = _controller.text.trim();
    final chars = text.length;
    final canSubmit = chars >= kMicroTaskMinChars;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFillHeader(palette, card),
          const SizedBox(height: AppSpacing.sm),
          _buildTaskBlock(palette, '任务', _promptText),
          const SizedBox(height: AppSpacing.sm),
          _buildTaskBlock(palette, '约束', card.constraint),
          const SizedBox(height: AppSpacing.sm),
          _buildTaskBlock(palette, '小钩子', card.hook),
          const SizedBox(height: AppSpacing.md),
          _buildEditor(palette),
          const SizedBox(height: AppSpacing.lg),
          _buildSubmitRow(palette, chars, canSubmit),
        ],
      ),
    );
  }

  /// 填写态头部：返回 + 标题 + 换一个
  Widget _buildFillHeader(AppPalette palette, MicroTaskCard card) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.arrow_back, size: 20, color: palette.textPrimary),
          tooltip: '返回卡片',
          onPressed: _backToList,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            card.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: _swapVariant,
          child: Text(
            '换一个',
            style: TextStyle(fontSize: 13, color: palette.primary),
          ),
        ),
      ],
    );
  }

  /// 填写态编辑器：输入框 + 字数提示
  Widget _buildEditor(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          maxLines: 8,
          minLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '在这里写你的素材……（写得烂也没关系）',
            filled: true,
            fillColor: palette.surfaceWhite,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildCharHint(palette, _controller.text.trim().length),
      ],
    );
  }

  /// 填写态提交行：提交按钮 + 素材练习声明
  Widget _buildSubmitRow(AppPalette palette, int chars, bool canSubmit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canSubmit ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: palette.primary,
              foregroundColor: palette.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              '提交 · 让教练诊断（$chars/$kMicroTaskMinChars 字）',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          kMicroTaskDisclaimer,
          style: TextStyle(fontSize: 12, color: palette.textTertiary),
        ),
      ],
    );
  }

  Widget _buildTaskBlock(AppPalette palette, String label, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharHint(AppPalette palette, int chars) {
    if (chars < kMicroTaskMinChars) {
      return Text(
        '再写一点，${kMicroTaskMinChars - chars} 字就到教练能看懂的门槛了',
        style: TextStyle(fontSize: 12, color: palette.textTertiary),
      );
    }
    if (chars > kMicroTaskSuggestMaxChars) {
      return Text(
        '已超过建议上限 $kMicroTaskSuggestMaxChars 字，仍可提交',
        style: TextStyle(fontSize: 12, color: palette.textTertiary),
      );
    }
    return Text(
      '写得越烂越好——教练要的就是你现在的真实水平',
      style: TextStyle(fontSize: 12, color: palette.textTertiary),
    );
  }
}

/// 列表态单卡
class _WallCard extends StatelessWidget {
  final MicroTaskCard card;
  final VoidCallback onTap;

  const _WallCard({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surfaceWhite,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: palette.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              card.prompt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
