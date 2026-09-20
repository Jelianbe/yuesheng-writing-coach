// ─────────────────────────────────────────────────────────────
// CharacterDialogs — 角色页五个弹层（C78 批次3）
//
//   showCreateCharacterDialog  新建角色（FR-7：名字必填 + 首见章节可选）
//   showAssertionFormDialog    断言表单（修正 / 补充共用；R-009 纯手动输入，
//                              无任何 AI 代填建议值）
//   showRejectReasonSheet      拒绝理由 chips（D-7：可选不强制，无自由文本）
//   showAliasEditDialog        别名编辑（FR-3：增删，去重去空）
//   showMergePickerDialog      并入主角色选源（D-5：目标页发起，选另一行）
//
// 统一约定：dismiss / 取消一律返回 null，调用方据此不做任何写。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../services/setting_library_service.dart';
import '../../types/character_types.dart';
import '../../utils/chapter_number.dart';
import '../../theme/app_typography.dart';

/// 新建角色结果：(名字, 首见章节?, 正文?（用户自由写作，正文优先）)
typedef CreateCharacterResult = ({
  String name,
  int? firstSeenChapter,
  String description,
});

/// 断言表单结果：(属性, 值, 章节?)
typedef AssertionFormResult = ({String attribute, String value, int? chapter});

/// 拒绝理由 chips（D-7 定稿四项，顺序即展示序）
const List<String> kRejectReasons = ['抽取错误', '章节已改写', '重复', '其他'];

Future<CreateCharacterResult?> showCreateCharacterDialog(BuildContext context) {
  final nameCtrl = TextEditingController();
  final chapterCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  return showDialog<CreateCharacterResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('新建角色', style: context.text.titleLg),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildCreateCharacterFields(
            nameCtrl,
            chapterCtrl,
            descCtrl,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            final chapter = int.tryParse(chapterCtrl.text.trim());
            Navigator.pop(ctx, (
              name: name,
              firstSeenChapter: chapter,
              description: descCtrl.text.trim(),
            ));
          },
          child: const Text('创建'),
        ),
      ],
    ),
  );
}

/// R-019 真分解：新建角色表单字段（名字 + 角色设定正文 + 首见章节，正文优先）。
List<Widget> _buildCreateCharacterFields(
  TextEditingController nameCtrl,
  TextEditingController chapterCtrl,
  TextEditingController descCtrl,
) {
  return [
    TextField(
      controller: nameCtrl,
      autofocus: true,
      decoration: const InputDecoration(labelText: '名字（必填）'),
    ),
    const SizedBox(height: AppSpacing.sm),
    TextField(
      controller: descCtrl,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(
        labelText: '角色设定（可选）',
        hintText: '先写下这个角色是谁——外貌、性格、背景、动机……',
        alignLabelWithHint: true,
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    TextField(
      controller: chapterCtrl,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(labelText: '首次登场章节（可选）'),
    ),
  ];
}

/// 断言表单：[title] 区分「补充断言」/「修正断言」；初值来自被修正条。
Future<AssertionFormResult?> showAssertionFormDialog(
  BuildContext context, {
  required String title,
  String? initialAttribute,
  String? initialValue,
  int? initialChapter,
  List<String> suggestions = const [],
}) {
  final attrCtrl = TextEditingController(text: initialAttribute ?? '');
  final valueCtrl = TextEditingController(text: initialValue ?? '');
  final chapterCtrl = TextEditingController(
    text: initialChapter?.toString() ?? '',
  );
  return showDialog<AssertionFormResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: context.text.titleLg),
      content: _AssertionFormFields(
        attrCtrl: attrCtrl,
        valueCtrl: valueCtrl,
        chapterCtrl: chapterCtrl,
        suggestions: suggestions,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final attr = attrCtrl.text.trim();
            final value = valueCtrl.text.trim();
            if (attr.isEmpty || value.isEmpty) return;
            Navigator.pop(ctx, (
              attribute: attr,
              value: value,
              chapter: int.tryParse(chapterCtrl.text.trim()),
            ));
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

/// 表单三个输入框（R-019 真分解：独立小组件）
class _AssertionFormFields extends StatelessWidget {
  final TextEditingController attrCtrl;
  final TextEditingController valueCtrl;
  final TextEditingController chapterCtrl;

  /// 属性名建议 chips（模板可学习：静态基础 + 作品内 user 属性 ≥2 次回填）
  final List<String> suggestions;

  const _AssertionFormFields({
    required this.attrCtrl,
    required this.valueCtrl,
    required this.chapterCtrl,
    this.suggestions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: attrCtrl,
          decoration: const InputDecoration(labelText: '属性（如：性格）'),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _AttributeSuggestionChips(
            suggestions: suggestions,
            onTap: (attr) {
              attrCtrl.text = attr;
              attrCtrl.selection = TextSelection.collapsed(
                offset: attrCtrl.text.length,
              );
            },
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: valueCtrl,
          decoration: const InputDecoration(labelText: '值（如：外冷内热）'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: chapterCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '章节（可选，如：7）'),
        ),
      ],
    );
  }
}

/// 属性名建议 chips（模板可学习；点击回填属性框，不强制）
class _AttributeSuggestionChips extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;

  const _AttributeSuggestionChips({
    required this.suggestions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('常用属性', style: context.text.microCaption),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final s in suggestions)
              ActionChip(
                label: Text(s, style: context.text.microCaption),
                visualDensity: VisualDensity.compact,
                onPressed: () => onTap(s),
              ),
          ],
        ),
      ],
    );
  }
}

/// 拒绝理由（D-7：可选不强制）。dismiss → null（不拒绝）；
/// 「跳过，直接拒绝」→ (confirmed: true, reason: null)。
Future<({bool confirmed, String? reason})?> showRejectReasonSheet(
  BuildContext context,
) {
  return showModalBottomSheet<({bool confirmed, String? reason})>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择拒绝理由（可选）', style: context.text.titleMd),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final reason in kRejectReasons)
                  ActionChip(
                    label: Text(reason),
                    onPressed: () =>
                        Navigator.pop(ctx, (confirmed: true, reason: reason)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, (confirmed: true, reason: null)),
                child: const Text('跳过，直接拒绝'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 别名编辑（FR-3）。返回编辑后的列表；dismiss → null。
Future<List<String>?> showAliasEditDialog(
  BuildContext context,
  List<String> current,
) {
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => _AliasEditorDialog(initial: current),
  );
}

/// 别名编辑弹窗（真分解：StatefulWidget 独立类，保存时 pop 结果列表）
class _AliasEditorDialog extends StatefulWidget {
  final List<String> initial;

  const _AliasEditorDialog({required this.initial});

  @override
  State<_AliasEditorDialog> createState() => _AliasEditorDialogState();
}

class _AliasEditorDialogState extends State<_AliasEditorDialog> {
  late final List<String> _aliases = [...widget.initial];
  final TextEditingController _ctrl = TextEditingController();

  void _add(String raw) {
    final v = raw.trim();
    if (v.isEmpty || _aliases.contains(v)) return;
    setState(() {
      _aliases.add(v);
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('编辑别名', style: context.text.titleLg),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('别名参与时序矛盾检测与相关事件关联（主名 ∪ 别名匹配）', style: context.text.caption),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xsm,
              runSpacing: AppSpacing.xsm,
              children: [
                for (var i = 0; i < _aliases.length; i++)
                  InputChip(
                    label: Text(_aliases[i]),
                    onDeleted: () => setState(() => _aliases.removeAt(i)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: '输入别名回车添加',
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _add(_ctrl.text),
                ),
              ),
              onSubmitted: _add,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _aliases),
          child: const Text('保存'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}

/// 并入主角色：从候选行（同作品其他 active 角色）里选源。
/// 候选为空 / dismiss → null。
Future<CharacterFact?> showMergePickerDialog(
  BuildContext context, {
  required List<CharacterFact> candidates,
}) {
  return showDialog<CharacterFact>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('并入主角色：选择要并入的重复行', style: context.text.titleLg),
      children: [
        if (candidates.isEmpty)
          Padding(
            padding: EdgeInsets.all(AppSpacing.section),
            child: Text('没有其他角色行可并入', style: context.text.body),
          )
        else
          for (final c in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.name, style: context.text.titleMd),
                subtitle: Text(
                  '该行的断言将迁入本角色，源名收进别名',
                  style: context.text.caption,
                ),
              ),
            ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.section),
          child: TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ),
      ],
    ),
  );
}

/// 疑似重复对照面板（AI 辅助比较）：A/B 两断言 + 三选一裁决。
///
/// [aiCompare] 非空时显示「AI 帮我比较」按钮（纯分析不代决，由调用方
/// 接 LlmClient）；返回 null = 用户取消（不落库）。
///
/// [chapterNoMap]（`N12-F3b` phase 2）：A/B 卡片上的章标**只吃身份载体**
/// （`chapterSortOrder`），**不是** `chapter`（一列三源、读时不可分辨）。
Future<MergeVerdict?> showConflictResolutionDialog(
  BuildContext context, {
  required AssertionConflictPair pair,
  required Map<int, int> chapterNoMap,
  Future<String> Function()? aiCompare,
}) {
  return showDialog<MergeVerdict>(
    context: context,
    builder: (ctx) => _ConflictResolutionDialog(
      pair: pair,
      chapterNoMap: chapterNoMap,
      aiCompare: aiCompare,
    ),
  );
}

class _ConflictResolutionDialog extends StatefulWidget {
  final AssertionConflictPair pair;
  final Map<int, int> chapterNoMap;
  final Future<String> Function()? aiCompare;

  const _ConflictResolutionDialog({
    required this.pair,
    required this.chapterNoMap,
    this.aiCompare,
  });

  @override
  State<_ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<_ConflictResolutionDialog> {
  bool _aiLoading = false;
  String? _aiAnalysis;

  Future<void> _runAiCompare() async {
    final fn = widget.aiCompare;
    if (fn == null) return;
    setState(() => _aiLoading = true);
    try {
      final text = await fn();
      if (!mounted) return;
      setState(() {
        _aiAnalysis = text;
        _aiLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiAnalysis = 'AI 比较失败（不影响你手动裁决）';
        _aiLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pair = widget.pair;
    return AlertDialog(
      title: Text('疑似重复：${pair.a.attribute}', style: context.text.titleLg),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConflictCard(
              label: 'A',
              assertion: pair.a,
              chapterNoMap: widget.chapterNoMap,
              onKeep: () => Navigator.pop(context, MergeVerdict.keepA),
            ),
            const SizedBox(height: AppSpacing.md),
            _ConflictCard(
              label: 'B',
              assertion: pair.b,
              chapterNoMap: widget.chapterNoMap,
              onKeep: () => Navigator.pop(context, MergeVerdict.keepB),
            ),
            _buildAiCompareSection(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, MergeVerdict.keepBoth),
          child: const Text('两者都保留'),
        ),
      ],
    );
  }

  /// R-019 拆分：AI 辅助比较区（按钮 + 分析结果）
  Widget _buildAiCompareSection(BuildContext context) {
    final widgets = <Widget>[];
    if (widget.aiCompare != null) {
      widgets.add(
        Align(
          alignment: Alignment.centerLeft,
          child: _aiLoading
              ? Text('AI 比较中…', style: context.text.microCaption)
              : TextButton.icon(
                  onPressed: _runAiCompare,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('AI 帮我比较（纯分析）'),
                ),
        ),
      );
    }
    if (_aiAnalysis != null) {
      widgets.addAll([
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Text(_aiAnalysis!, style: context.text.subBody),
        ),
      ]);
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        ...widgets,
      ],
    );
  }
}

/// 冲突单卡：断言 + 保留按钮（A/B 共用）
class _ConflictCard extends StatelessWidget {
  final String label;
  final CharacterAssertion assertion;
  final Map<int, int> chapterNoMap;
  final VoidCallback onKeep;

  const _ConflictCard({
    required this.label,
    required this.assertion,
    required this.chapterNoMap,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    // `N12-F3b` phase 2：章标**只吃身份载体**，无身份 ⇒ 「未标注」。
    // **不回退到 `assertion.chapter`** —— 那是 AI 标称号，回退会显示一个错的号（`S1`）。
    final chapter =
        chapterLabel(chapterNoMap, assertion.chapterSortOrder) ?? '未标注';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          radius: 14,
          child: Text(label, style: context.text.microCaption),
        ),
        title: Text(
          '${assertion.attribute} = ${assertion.value}',
          style: context.text.body,
        ),
        subtitle: Text('来源：$chapter', style: context.text.microCaption),
        trailing: FilledButton.tonal(
          onPressed: onKeep,
          child: const Text('保留'),
        ),
      ),
    );
  }
}
