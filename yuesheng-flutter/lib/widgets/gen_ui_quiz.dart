// ─────────────────────────────────────────────────────────────
// GenUiQuiz — quiz 组件（B-1 GenUI v1）
//
// 「练→评」闭环的交互载体：训练选择题 + 本地判分 + 解释。
// 判分复用 training_evaluator 的「本地优先」原则——零模型往返。
//
// 哲学红线（R-009）：quiz 仅用于训练检验，不用于替用户判断作品好坏；
// 无 action 按钮渲染为禁用（dsh-genui 诚实交互）。
//
// 持久化：提交后把 userAnswers/results/answered 写回 genui 消息 content
// （按 messageId 关联，重启不丢），不走新表、不迁移。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../providers/app_providers.dart';
import '../data/repositories/session_repository.dart';
import '../services/message_card_service.dart';

class GenUiQuiz extends ConsumerStatefulWidget {
  final String? messageId;
  final GenuiCardPayload payload;
  final int index;
  final Map<String, dynamic> data;

  const GenUiQuiz({
    required this.messageId,
    required this.payload,
    required this.index,
    required this.data,
    super.key,
  });

  @override
  ConsumerState<GenUiQuiz> createState() => _GenUiQuizState();
}

class _GenUiQuizState extends ConsumerState<GenUiQuiz> {
  late final List<Map<String, dynamic>> _items;
  late List<int?> _selected;
  late bool _submitted;
  late List<bool> _results;

  @override
  void initState() {
    super.initState();
    final rawItems = widget.data['items'];
    _items = (rawItems is List)
        ? rawItems
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];
    final restored = widget.data['userAnswers'];
    _selected = (_items.asMap().keys).map((i) {
      if (restored is List && i < restored.length && restored[i] is int) {
        return restored[i] as int;
      }
      return null;
    }).toList();
    _submitted = widget.data['answered'] == true;
    final restoredResults = widget.data['results'];
    _results = (_items.asMap().keys).map((i) {
      if (restoredResults is List && i < restoredResults.length) {
        return restoredResults[i] == true;
      }
      return false;
    }).toList();
  }

  bool get _allAnswered => _selected.every((s) => s != null);

  int get _correctCount => _results.where((r) => r).length;

  void _onSubmit() {
    if (!_allAnswered) return;
    final results = <bool>[];
    for (var i = 0; i < _items.length; i++) {
      final answer = _items[i]['answer'];
      results.add(_selected[i] == answer);
    }
    setState(() {
      _results = results;
      _submitted = true;
    });
    _persist(results);
  }

  Future<void> _persist(List<bool> results) async {
    if (widget.messageId == null) return;
    widget.payload.components[widget.index].data['userAnswers'] =
        List<int?>.from(_selected);
    widget.payload.components[widget.index].data['results'] = results;
    widget.payload.components[widget.index].data['answered'] = true;
    final newContent = jsonEncode(widget.payload.toJson());
    try {
      final repo = SessionRepository(ref.read(appDatabaseProvider));
      await repo.updateMessageContent(widget.messageId!, newContent);
    } catch (e) {
      debugPrint('[GenUiQuiz] 答题状态持久化失败（不阻断）: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.data['title'] as String?;
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
        ..._items.asMap().entries.map((e) => _buildItem(e.key, e.value)),
        const SizedBox(height: 8),
        _buildFooter(),
      ],
    );
  }

  Widget _buildItem(int itemIdx, Map<String, dynamic> item) {
    final question = (item['q'] as String?) ?? '';
    final options = (item['options'] is List)
        ? (item['options'] as List).map((o) => o.toString()).toList()
        : <String>[];
    final explanation = item['explanation'] as String?;
    final chosen = _selected[itemIdx];
    final isCorrect = _results.length > itemIdx ? _results[itemIdx] : false;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.smx),
      padding: const EdgeInsets.all(AppSpacing.smx),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${itemIdx + 1}. $question',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          ...options.asMap().entries.map((o) {
            final optIdx = o.key;
            final optText = o.value;
            final isChosen = chosen == optIdx;
            Color? tileColor;
            Color? textColor;
            if (_submitted) {
              if (isChosen && isCorrect) {
                tileColor = AppColors.successBg;
                textColor = AppColors.success;
              } else if (isChosen && !isCorrect) {
                tileColor = AppColors.dangerBg;
                textColor = AppColors.danger;
              }
            }
            return GestureDetector(
              onTap: _submitted
                  ? null
                  : () => setState(() => _selected[itemIdx] = optIdx),
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smx,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color:
                      tileColor ??
                      (isChosen
                          ? AppColors.primarySoft
                          : AppColors.surfaceWhite),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isChosen ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        optText,
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor ?? AppColors.textBody,
                        ),
                      ),
                    ),
                    if (_submitted && isChosen)
                      Icon(
                        isCorrect ? Icons.check_circle : Icons.cancel,
                        size: 16,
                        color: textColor,
                      ),
                  ],
                ),
              ),
            );
          }),
          if (_submitted && explanation != null && explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '解析：$explanation',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    if (_submitted) {
      final total = _items.length;
      return Row(
        children: [
          Icon(
            _correctCount == total
                ? Icons.emoji_events
                : Icons.lightbulb_outline,
            size: 16,
            color: _correctCount == total
                ? AppColors.success
                : AppColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            '答对 $_correctCount / $total',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _correctCount == total
                  ? AppColors.success
                  : AppColors.textPrimary,
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _allAnswered ? _onSubmit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.disabledText,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.smx),
        ),
        child: Text(_allAnswered ? '提交' : '请完成所有题目'),
      ),
    );
  }
}
