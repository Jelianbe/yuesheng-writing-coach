// ─────────────────────────────────────────────────────────────
// GenUICard — GenUI 协议块渲染（B-1 GenUI v1）
//
// 由 dispatchMessageCard 在 messageType=='genui' 时分派。
// 解析 content(JSON) → GenuiCardPayload → 按 type 渲染子组件。
//
// 哲学红线（R-009 不替写不替决定）：
// - diff：仅展示用户已完成的改写对比，无「采纳模型改写」按钮
// - quiz：仅训练检验，本地判分零模型往返（见 gen_ui_quiz.dart）
// - 白名单外 / 占位类型：诚实渲染「暂未支持」，无假按钮（dsh-genui 诚实交互）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/genui_parser.dart';
import '../services/message_card_service.dart';
import 'gen_ui_quiz.dart';

class GenUICard extends StatelessWidget {
  final String content;
  final String? messageId;

  const GenUICard.fromMessageContent(
    this.content, {
    this.messageId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final payload = _safeParse(content);
    if (payload == null || payload.components.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GenUiHeader(),
          const SizedBox(height: 8),
          ...payload.components.asMap().entries.map(
                (e) => _renderComponent(e.value, payload, e.key),
              ),
        ],
      ),
    );
  }

  GenuiCardPayload? _safeParse(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      return GenuiCardPayload.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Widget _renderComponent(GenUiComponent c, GenuiCardPayload payload, int index) {
    switch (c.type) {
      case 'diff':
        return _GenUiDiff(data: c.data);
      case 'quiz':
        return GenUiQuiz(
          messageId: messageId,
          payload: payload,
          index: index,
          data: c.data,
        );
      default:
        return _GenUiPlaceholder(type: c.type, data: c.data);
    }
  }
}

class _GenUiHeader extends StatelessWidget {
  const _GenUiHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.auto_awesome_outlined, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          '交互组件',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

/// diff 组件：展示用户已完成的改写对比（原文 vs 改写）
///
/// 仅展示，无「采纳」按钮（R-009：不替用户决定）。
class _GenUiDiff extends StatelessWidget {
  final Map<String, dynamic> data;

  const _GenUiDiff({required this.data});

  @override
  Widget build(BuildContext context) {
    final before = (data['before'] as String?) ?? '';
    final after = (data['after'] as String?) ?? '';
    final title = data['title'] as String?;
    final note = data['note'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _DiffPanel(label: '原文', text: before)),
            const SizedBox(width: 8),
            Expanded(child: _DiffPanel(label: '改写', text: after, emphasis: true)),
          ],
        ),
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            note,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _DiffPanel extends StatelessWidget {
  final String label;
  final String text;
  final bool emphasis;

  const _DiffPanel({
    required this.label,
    required this.text,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: emphasis ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: emphasis ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: emphasis ? AppColors.primary : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text.isEmpty ? '（空）' : text,
            style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// 占位组件：白名单内但 v1 暂未完整实现的类型（stat/progress/timeline）
///
/// 诚实渲染「暂未支持」，不提供假按钮（dsh-genui 诚实交互原则）。
class _GenUiPlaceholder extends StatelessWidget {
  final String type;
  final Map<String, dynamic> data;

  const _GenUiPlaceholder({required this.type, required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String?;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '「$type」组件${title != null ? '（$title）' : ''}将在后续版本支持',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
