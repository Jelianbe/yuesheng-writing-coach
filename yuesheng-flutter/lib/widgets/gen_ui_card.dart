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

  const GenUICard.fromMessageContent(this.content, {this.messageId, super.key});

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

  Widget _renderComponent(
    GenUiComponent c,
    GenuiCardPayload payload,
    int index,
  ) {
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
      case 'stat':
        return _GenUiStat(data: c.data);
      case 'progress':
        return _GenUiProgress(data: c.data);
      case 'timeline':
        return _GenUiTimeline(data: c.data);
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
            Expanded(
              child: _DiffPanel(label: '原文', text: before),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DiffPanel(label: '改写', text: after, emphasis: true),
            ),
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
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// stat 组件：能力维度卡片（五维文笔画像展示）
///
/// 数据格式：{title?, items:[{label, value, max}]}
/// 每个维度渲染为「标签 + 进度条 + 数值」行。
/// value/max 缺失时降级为 0；items 缺失或空时显示占位提示。
class _GenUiStat extends StatelessWidget {
  final Map<String, dynamic> data;

  const _GenUiStat({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String?;
    final rawItems = data['items'];
    final items = (rawItems is List)
        ? rawItems
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];

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
        if (items.isEmpty)
          Text(
            '（无维度数据）',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          )
        else
          ...items.map(
            (m) => _StatBar(
              label: (m['label'] as String?) ?? '',
              value: (m['value'] as num?)?.toDouble() ?? 0,
              max: (m['max'] as num?)?.toDouble() ?? 100,
            ),
          ),
      ],
    );
  }
}

class _StatBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;

  const _StatBar({required this.label, required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: AppColors.borderSoft,
                valueColor: AlwaysStoppedAnimation<Color>(
                  ratio >= 0.8 ? AppColors.success : AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              '${value.toInt()}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ratio >= 0.8 ? AppColors.success : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// progress 组件：训练进度/六步闭环进度
///
/// 数据格式：{title?, steps:[{label, status:"done"|"current"|"pending"}]}
/// 渲染为横向步骤指示器：已完成(✓竹青) → 当前(竹青实心) → 待完成(灰圈)。
class _GenUiProgress extends StatelessWidget {
  final Map<String, dynamic> data;

  const _GenUiProgress({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String?;
    final rawSteps = data['steps'];
    final steps = (rawSteps is List)
        ? rawSteps
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];

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
          const SizedBox(height: 10),
        ],
        if (steps.isEmpty)
          Text(
            '（无步骤数据）',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          )
        else
          _ProgressRow(steps: steps),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final List<Map<String, dynamic>> steps;

  const _ProgressRow({required this.steps});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _ProgressNode(
              label: (steps[i]['label'] as String?) ?? '',
              status: (steps[i]['status'] as String?) ?? 'pending',
            ),
            if (i < steps.length - 1)
              _ProgressConnector(
                done: (steps[i]['status'] as String?) == 'done',
              ),
          ],
        ],
      ),
    );
  }
}

class _ProgressNode extends StatelessWidget {
  final String label;
  final String status; // done | current | pending

  const _ProgressNode({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final isDone = status == 'done';
    final isCurrent = status == 'current';
    final color = isDone
        ? AppColors.success
        : isCurrent
        ? AppColors.primary
        : AppColors.textTertiary;
    final bgColor = isDone
        ? AppColors.successBg
        : isCurrent
        ? AppColors.primarySoft
        : AppColors.surface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: isCurrent ? 2 : 1),
          ),
          alignment: Alignment.center,
          child: isDone
              ? Icon(Icons.check, size: 16, color: color)
              : Text('', style: TextStyle(fontSize: 12, color: color)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 56,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDone || isCurrent
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressConnector extends StatelessWidget {
  final bool done;

  const _ProgressConnector({required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 2,
      margin: const EdgeInsets.only(bottom: 20),
      color: done ? AppColors.success : AppColors.borderSoft,
    );
  }
}

/// timeline 组件：GrowthChain 成长证据链
///
/// 数据格式：{title?, events:[{date, title, desc?}]}
/// 渲染为纵向时间线：每个事件一个节点 + 日期/标题/描述卡片。
class _GenUiTimeline extends StatelessWidget {
  final Map<String, dynamic> data;

  const _GenUiTimeline({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String?;
    final rawEvents = data['events'];
    final events = (rawEvents is List)
        ? rawEvents
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
        : <Map<String, dynamic>>[];

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
          const SizedBox(height: 10),
        ],
        if (events.isEmpty)
          Text(
            '（无成长记录）',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          )
        else
          ...events.asMap().entries.map(
            (e) => _TimelineEntry(
              isLast: e.key == events.length - 1,
              date: (e.value['date'] as String?) ?? '',
              title: (e.value['title'] as String?) ?? '',
              desc: e.value['desc'] as String?,
            ),
          ),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final bool isLast;
  final String date;
  final String title;
  final String? desc;

  const _TimelineEntry({
    required this.isLast,
    required this.date,
    required this.title,
    this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧时间线轨道
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.borderSoft,
                      margin: const EdgeInsets.only(top: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧内容卡片
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (date.isNotEmpty)
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (desc != null && desc!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      desc!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 占位组件：白名单外或数据缺失的兜底渲染
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
