// ─────────────────────────────────────────────────────────────
// SelectionAiSheet — 划词选区 AI 菜单完整版（批次83 划词菜单完整版）
// 番茄范式：生成结果可择选 + 换一换（AI 给参考，人做决定）
//
// 三种模式共用同一弹层，仅 prompt 与落稿动作不同：
//   - 改写（rewrite）    ：生成 3 个改写版本 → 「用这个」替换选区
//   - 续写（continueWrite）：生成 3 个续写走向 → 「用这个」插入选区之后
//   - 扩写（expand）     ：生成 3 个扩写版本 → 「用这个」替换选区
//
// 交互：
//   - 打开即调 LLM 非流式生成（chatCompletion），解析出 N 个版本
//   - 每个版本卡片「用这个」→ 回调 onAdopt 由写作页落稿
//   - 底部「换一换」→ 重新生成一批
//
// 解析策略（parseSelectionVersions）：
//   - 优先按「【版本一】…【版本二】…」标记切分
//   - 兜底按编号行（1. 2. 3.）切分
//   - 兜底整段当一个版本（AI 没按格式时至少可用）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../providers/session_providers.dart';
import '../services/llm_client.dart';
import 'yue_sheet.dart';

/// 划词 AI 生成模式
enum SelectionAiMode { rewrite, continueWrite, expand }

/// 模式 → 弹层标题
String selectionAiModeTitle(SelectionAiMode mode) {
  switch (mode) {
    case SelectionAiMode.rewrite:
      return '改写这段';
    case SelectionAiMode.continueWrite:
      return '续写这段';
    case SelectionAiMode.expand:
      return '扩写这段';
  }
}

/// 解析 LLM 输出为多个版本（按【版本N】标记 / 编号行 / 整段兜底）
List<String> parseSelectionVersions(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];

  // 1. 【版本一】【版本二】…标记切分（仅当文本确实含标记）
  final markerRe = RegExp(r'【版本[一二三四五]】');
  if (markerRe.hasMatch(text)) {
    final markedParts = text
        .split(markerRe)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (markedParts.isNotEmpty) return markedParts;
  }

  // 2. 编号行切分（1. 2. 3. / 1、2、3、）
  final numbered = text.split(
    RegExp(r'^\s*[1-3][.、]\s*', multiLine: true),
  );
  final numberedParts = numbered
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (numberedParts.length >= 2) return numberedParts;

  // 3. 兜底：整段当一个版本
  return [text];
}

class SelectionAiSheet {
  const SelectionAiSheet._();

  /// 打开择选弹层；[onAdopt] 收到用户选中的版本正文（写作页负责落稿）
  static Future<void> show(
    BuildContext context, {
    required SelectionAiMode mode,
    required String selectedText,
    required void Function(String chosen) onAdopt,
  }) {
    return showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SelectionAiSheetContent(
        mode: mode,
        selectedText: selectedText,
        onAdopt: (chosen) {
          Navigator.pop(ctx);
          onAdopt(chosen);
        },
      ),
    );
  }
}

class _SelectionAiSheetContent extends ConsumerStatefulWidget {
  final SelectionAiMode mode;
  final String selectedText;
  final ValueChanged<String> onAdopt;

  const _SelectionAiSheetContent({
    required this.mode,
    required this.selectedText,
    required this.onAdopt,
  });

  @override
  ConsumerState<_SelectionAiSheetContent> createState() =>
      _SelectionAiSheetContentState();
}

class _SelectionAiSheetContentState extends ConsumerState<_SelectionAiSheetContent> {
  bool _loading = false;
  String? _error;
  List<String> _versions = const [];

  @override
  void initState() {
    super.initState();
    _generate();
  }

  /// 请求 LLM 生成一批版本（打开时 + 换一换时）
  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final llm = ref.read(llmClientProvider);
      final raw = await llm.chatCompletion([
        ChatMessage(role: 'user', content: _buildPrompt(widget.mode, widget.selectedText)),
      ]);
      final versions = parseSelectionVersions(raw);
      if (!mounted) return;
      if (versions.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'AI 这次没写出来，换个姿势再试试吧';
        });
        return;
      }
      setState(() {
        _loading = false;
        _versions = versions;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '生成失败，稍后再试一次吧';
      });
    }
  }

  /// 模式 → 生成 prompt（要求 3 个版本 + 明确标记，便于解析）
  String _buildPrompt(SelectionAiMode mode, String selectedText) {
    switch (mode) {
      case SelectionAiMode.rewrite:
        return '请把下面的文字改写为 3 个不同版本，忠实原意，分别侧重更有画面感、更简洁凝练、更口语自然。'
            '每个版本以【版本一】【版本二】【版本三】开头，只输出正文，不要任何解释。\n\n$selectedText';
      case SelectionAiMode.continueWrite:
        return '请接着下面的文字继续写下去，给出 3 个不同走向的续写（每个 80-150 字），'
            '以【版本一】【版本二】【版本三】开头，只输出正文，不要任何解释。\n\n$selectedText';
      case SelectionAiMode.expand:
        return '请把下面的文字扩写为 3 个不同版本，补充细节让内容更丰满（每个 200 字以内），'
            '以【版本一】【版本二】【版本三】开头，只输出正文，不要任何解释。\n\n$selectedText';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = selectionAiModeTitle(widget.mode);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 头部：标题 + 关闭 ──
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textInk,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── 原文预览 ──
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              widget.selectedText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── 加载 / 错误 / 版本列表 ──
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '正在帮你写几个版本…',
                    style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                  ),
                ],
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _generate,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _versions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _buildVersionCard(
                  context,
                  index: index,
                  version: _versions[index],
                ),
              ),
            ),
          const SizedBox(height: 14),
          // ── 换一换 ──
          OutlinedButton.icon(
            onPressed: _loading ? null : _generate,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.textSecondary,
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('换一换'),
          ),
        ],
      ),
    );
  }

  /// 版本卡片：版本 N 标签 + 用这个 + 正文
  Widget _buildVersionCard(
    BuildContext context, {
    required int index,
    required String version,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '版本 ${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: FilledButton(
                  onPressed: () => widget.onAdopt(version),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('用这个', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            version,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textBody,
            ),
          ),
        ],
      ),
    );
  }
}
