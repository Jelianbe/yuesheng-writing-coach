// ─────────────────────────────────────────────────────────────
// PremiseTeachingCard — 题材定位·教练笔记卡（T-20261110-13 · 甲裁定实现）
//
// 对话流内嵌、默认收起的教学卡：附着在触发轮 assistant 回应下方。
// 内容 = 训练KB P031 节四段（核心本质/教学要点/常见误区/教学素材库，
// U3 签核裁定：**跳过「严重度判断参考」小节**——卡面不露判级语境，N2）。
// 逐字渲染本地常量（kTrainingFullKnowledge 单一真源提取），不依赖模型输出。
// 视觉家族参照 diagnosis_card 的 palette 驱动用法，去诊断语义元素
// （无症候编号、无严重度色、无「本次诊断」头）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../services/premise_trigger.dart';
import '../services/training_knowledge_base.dart';

/// 卡标题（用户可见文案 · 报批稿 ④-6 登记面）
const String kPremiseCardTitle = '题材定位 · 教练笔记';

/// 四段小节标记（KB 节内粗体标题；渲染顺序即展开顺序）
const List<String> _kCardSectionMarkers = [
  '**核心本质**',
  '**教学要点**',
  '**常见误区**',
  '**教学素材库**',
];

/// 从训练KB P031 节切出四段（跳过「严重度判断参考」——U3 签核裁定）。
/// 返回 (标题, 正文) 对；标记缺失的段跳过（防御：KB 异常时不渲染残段）。
List<(String, String)> premiseCardSections(String kbSection) {
  final result = <(String, String)>[];
  for (final marker in _kCardSectionMarkers) {
    final start = kbSection.indexOf(marker);
    if (start == -1) continue;
    // 段终点 = 下一个 '**' 粗体标记（或节尾）
    var end = kbSection.length;
    for (final other in _kCardSectionMarkers) {
      if (other == marker) continue;
      final o = kbSection.indexOf(other, start + marker.length);
      if (o != -1 && o < end) end = o;
    }
    // 「严重度判断参考」段若夹在中间同样截断（按任意 ** 标记）
    final sevIdx = kbSection.indexOf('**严重度判断参考**', start);
    if (sevIdx > start && sevIdx < end) end = sevIdx;
    final title = marker.replaceAll('**', '');
    result.add((title, kbSection.substring(start, end).trim()));
  }
  return result;
}

class PremiseTeachingCard extends StatefulWidget {
  /// 卡是否默认展开（测试用；生产默认收起）。
  final bool initiallyExpanded;

  const PremiseTeachingCard({super.key, this.initiallyExpanded = false});

  /// 该 assistant 消息是否应附本卡（触发轮回应判定 + 每会话只渲染一张，R4）。
  ///
  /// 判定 = 从消息流推断（零 DB 字段、零落库改动）：找消息序列中**第一个**
  /// 「键入文本命中关键词集 K 的 user 消息」，其后**第一条** assistant 消息
  /// 即为附着目标；当前 index 命中该目标 ⇒ true，其余（含第二张候选）⇒ false。
  static bool shouldAttachCard(
    List<Map<String, dynamic>> renderItems,
    int index,
  ) {
    String? lastUserText;
    for (var i = 0; i < renderItems.length; i++) {
      final msg = renderItems[i]['data'] as Message;
      if (msg.role == 'user') {
        lastUserText = msg.content;
        continue;
      }
      if (msg.role == 'assistant' && lastUserText != null) {
        if (premiseTopicHit(lastUserText)) {
          // 第一个触发轮已找到：目标 = 其后第一条 assistant
          return i == index;
        }
        lastUserText = null; // 非触发轮：继续找下一个 user
      }
    }
    return false;
  }

  @override
  State<PremiseTeachingCard> createState() => _PremiseTeachingCardState();
}

class _PremiseTeachingCardState extends State<PremiseTeachingCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final kb = extractPremiseKbSection();
    final sections = kb == null
        ? const <(String, String)>[]
        : premiseCardSections(kb);
    final palette = context.palette;
    return Material(
      color: palette.surfaceWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.borderSoft, width: 0.5),
          ),
          child: _expanded
              ? _buildExpanded(palette, sections)
              : _buildCollapsed(palette),
        ),
      ),
    );
  }

  /// 收起态：单行卡头（≥48dp 命中区由 InkWell 全头承担）。
  Widget _buildCollapsed(AppPalette palette) {
    return Row(
      children: [
        Icon(Icons.lightbulb_outline, size: 16, color: palette.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            kPremiseCardTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.textPrimary,
            ),
          ),
        ),
        Icon(Icons.expand_more, size: 18, color: palette.textTertiary),
      ],
    );
  }

  /// 展开态：卡头 + 四段（R3 断言锚 = 四段标题）。
  Widget _buildExpanded(AppPalette palette, List<(String, String)> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 16, color: palette.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                kPremiseCardTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Icon(Icons.expand_less, size: 18, color: palette.textTertiary),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final (title, body) in sections) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _stripBoldMarkers(body),
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  /// 卡面为纯文本渲染：剥掉 markdown 粗体标记（内容零改动，只去装饰）。
  static String _stripBoldMarkers(String s) => s.replaceAll('**', '');
}

/// KB 提取薄封装（供卡与测试共用；返回 null = 知识库异常，卡面空态兜底）。
String? extractPremiseKbSection() {
  final pattern = RegExp('^## P031 ', multiLine: true);
  final match = pattern.firstMatch(kTrainingFullKnowledge);
  if (match == null) return null;
  final next = kTrainingFullKnowledge.indexOf('\n## ', match.start + 1);
  final end = next != -1 ? next : kTrainingFullKnowledge.length;
  return kTrainingFullKnowledge.substring(match.start, end).trim();
}
