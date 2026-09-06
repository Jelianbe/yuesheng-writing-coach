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

/// 新建角色结果：(名字, 首见章节?)
typedef CreateCharacterResult = ({String name, int? firstSeenChapter});

/// 断言表单结果：(属性, 值, 章节?)
typedef AssertionFormResult = ({String attribute, String value, int? chapter});

/// 拒绝理由 chips（D-7 定稿四项，顺序即展示序）
const List<String> kRejectReasons = ['抽取错误', '章节已改写', '重复', '其他'];

Future<CreateCharacterResult?> showCreateCharacterDialog(BuildContext context) {
  final nameCtrl = TextEditingController();
  final chapterCtrl = TextEditingController();
  return showDialog<CreateCharacterResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建角色', style: AppTextStyles.titleLg),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名字（必填）'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: chapterCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '首次登场章节（可选）'),
          ),
        ],
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
            Navigator.pop(ctx, (name: name, firstSeenChapter: chapter));
          },
          child: const Text('创建'),
        ),
      ],
    ),
  );
}

/// 断言表单：[title] 区分「补充断言」/「修正断言」；初值来自被修正条。
Future<AssertionFormResult?> showAssertionFormDialog(
  BuildContext context, {
  required String title,
  String? initialAttribute,
  String? initialValue,
  int? initialChapter,
}) {
  final attrCtrl = TextEditingController(text: initialAttribute ?? '');
  final valueCtrl = TextEditingController(text: initialValue ?? '');
  final chapterCtrl = TextEditingController(
    text: initialChapter?.toString() ?? '',
  );
  return showDialog<AssertionFormResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppTextStyles.titleLg),
      content: _AssertionFormFields(
        attrCtrl: attrCtrl,
        valueCtrl: valueCtrl,
        chapterCtrl: chapterCtrl,
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

  const _AssertionFormFields({
    required this.attrCtrl,
    required this.valueCtrl,
    required this.chapterCtrl,
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
            const Text('选择拒绝理由（可选）', style: AppTextStyles.titleMd),
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
      title: const Text('编辑别名', style: AppTextStyles.titleLg),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('别名参与时序矛盾检测与相关事件关联（主名 ∪ 别名匹配）', style: AppTextStyles.caption),
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
      title: const Text('并入主角色：选择要并入的重复行', style: AppTextStyles.titleLg),
      children: [
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.section),
            child: Text('没有其他角色行可并入', style: AppTextStyles.body),
          )
        else
          for (final c in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.name, style: AppTextStyles.titleMd),
                subtitle: Text(
                  '该行的断言将迁入本角色，源名收进别名',
                  style: AppTextStyles.caption,
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
