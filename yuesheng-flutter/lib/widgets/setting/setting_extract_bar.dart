// ─────────────────────────────────────────────────────────────
// setting_extract_bar — 「从正文提炼断言」条（创建体验 A2）
//
// 挂在角色/世界观详情页：正文非空时显示，点击调 LLM 把正文提炼为
// pending 断言（增量合并落库，不覆盖既有）。失败降级 SnackBar。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../providers/session_providers.dart';
import '../../services/setting_assertion_extractor.dart';
import '../../types/character_types.dart';

/// 提炼结果回调（落库 + 刷新由宿主负责）。
class SettingExtractBar extends ConsumerStatefulWidget {
  final String manuscriptId;
  final String entityName;

  /// 正文（非空才显示本条）。
  final String description;

  /// 提炼断言按此章节标注（角色/世界观首见章节）。
  final int? chapter;

  /// 落库：增量合并写入（upsertCharacter 语义），返回最新断言数。
  final Future<int> Function(List<CharacterAssertion> extracted) onExtracted;

  const SettingExtractBar({
    super.key,
    required this.manuscriptId,
    required this.entityName,
    required this.description,
    required this.chapter,
    required this.onExtracted,
  });

  @override
  ConsumerState<SettingExtractBar> createState() => _SettingExtractBarState();
}

class _SettingExtractBarState extends ConsumerState<SettingExtractBar> {
  bool _busy = false;

  Future<void> _extract() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final extractor = SettingAssertionExtractor(ref.read(llmClientProvider));
      final extracted = await extractor.extractFromText(
        entityName: widget.entityName,
        text: widget.description,
        chapter: widget.chapter,
      );
      if (!mounted) return;
      if (extracted.isEmpty) {
        _toast('未能从正文中提炼出断言，可尝试补充正文内容');
        return;
      }
      final total = await widget.onExtracted(extracted);
      if (!mounted) return;
      _toast('已提炼 ${extracted.length} 条断言（待确认），现有共 $total 条');
    } catch (_) {
      if (!mounted) return;
      _toast('提炼失败：请确认已配置模型服务，或稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.description.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _extract,
        icon: _busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome, size: 16),
        label: Text(_busy ? '提炼中…' : '从正文提炼断言'),
      ),
    );
  }
}
