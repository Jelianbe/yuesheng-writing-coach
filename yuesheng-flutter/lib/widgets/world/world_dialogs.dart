// ─────────────────────────────────────────────────────────────
// world_dialogs — 世界观手动录入的三个弹层（批次 W1）
//
//   showCreateWorldThemeDialog    新建主题（含首条设定断言，R2）
//   showAppendAssertionDialog     追加断言到既有主题（R4）
//   showArchiveWorldConfirmDialog 归档确认（R5，中性动词「归档」，无「删除」字样）
//
// 统一约定（照搬 character_dialogs.dart）：dismiss / 取消一律返回 null，
// 调用方据此不做任何写。
//
// 承 A2/R6：新建与追加表单**强制含「原文依据」**字段，并常驻一行说明
// （[kWorldEvidenceHint]）——「填了才进一致性检查，留空仅记录」。这是
// 零判据改动（A4）即可让录入生效的唯一路径（判据 `_hasEvidence` 门槛）。
// 提示为**静态文案**，不做弹窗拦截、不强制必填（承 Q2 暂定值）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

/// 新建主题结果：(主题名, 属性?, 取值?, 章节?, 原文依据?)
///
/// 属性与取值**同为 null** = 只建空主题（Q3 暂定：允许）；
/// 一空一非空被表单拦截，不会出现在结果里。
typedef CreateWorldThemeResult = ({
  String name,
  String description,
  String? attribute,
  String? value,
  int? chapter,
  String? evidence,
});

/// 追加断言结果：(属性, 取值, 章节?, 原文依据?)
typedef AppendAssertionResult = ({
  String attribute,
  String value,
  int? chapter,
  String? evidence,
});

/// 「原文依据」字段下方的常驻说明（R6 / Q2 唯一措辞，逐字，不得改写）。
const String kWorldEvidenceHint = 'ⓘ 填了「原文依据」的设定才会参与一致性检查；留空则仅记录、不参与。';

/// 空主题（无有效断言）在列表项上的视觉标识文案（Q3）。
const String kWorldThemeEmptyHint = '暂无设定';

/// 新建主题弹层（R2）：主题名必填 + 首条设定（属性 / 取值 / 章节 / 原文依据）。
Future<CreateWorldThemeResult?> showCreateWorldThemeDialog(
  BuildContext context,
) {
  return showDialog<CreateWorldThemeResult>(
    context: context,
    builder: (_) => const _CreateWorldThemeDialog(),
  );
}

/// 追加断言弹层（R4）：与新建的断言组同款（含「原文依据」），顶部显示目标主题只读名。
Future<AppendAssertionResult?> showAppendAssertionDialog(
  BuildContext context, {
  required String themeName,
}) {
  return showDialog<AppendAssertionResult>(
    context: context,
    builder: (_) => _AppendAssertionDialog(themeName: themeName),
  );
}

/// 归档确认弹层（R5）：中性动词「归档」，文案明示「数据保留（归档非删除）」。
Future<bool?> showArchiveWorldConfirmDialog(
  BuildContext context, {
  required String themeName,
  required int assertionCount,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('归档设定主题', style: AppTextStyles.titleLg),
      content: Text(
        '归档「$themeName」？\n\n'
        '· 该主题及其 $assertionCount 条设定将不再出现在列表中\n'
        '· 不再参与一致性检查\n'
        '· 数据保留（归档非删除）',
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('归档'),
        ),
      ],
    ),
  );
}

/// 新建主题弹层（真分解：StatefulWidget 独立类，本地 error 状态）。
class _CreateWorldThemeDialog extends StatefulWidget {
  const _CreateWorldThemeDialog();

  @override
  State<_CreateWorldThemeDialog> createState() =>
      _CreateWorldThemeDialogState();
}

class _CreateWorldThemeDialogState extends State<_CreateWorldThemeDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _attrCtrl = TextEditingController();
  final TextEditingController _valueCtrl = TextEditingController();
  final TextEditingController _chapterCtrl = TextEditingController();
  final TextEditingController _evidenceCtrl = TextEditingController();
  String? _nameError;
  String? _assertionError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _attrCtrl.dispose();
    _valueCtrl.dispose();
    _chapterCtrl.dispose();
    _evidenceCtrl.dispose();
    super.dispose();
  }

  /// 校验并回传（§6-C 主题名空 / §6-D 属性取值一空一非空；两者皆空 = 建空主题）。
  void _submit() {
    final name = _nameCtrl.text.trim();
    final attr = _attrCtrl.text.trim();
    final value = _valueCtrl.text.trim();
    setState(() {
      _nameError = name.isEmpty ? '请填写主题名' : null;
      _assertionError = attr.isEmpty != value.isEmpty ? '属性和取值不能为空' : null;
    });
    if (_nameError != null || _assertionError != null) return;
    final evidence = _evidenceCtrl.text.trim();
    Navigator.pop(context, (
      name: name,
      description: _descCtrl.text.trim(),
      attribute: attr.isEmpty ? null : attr,
      value: value.isEmpty ? null : value,
      chapter: int.tryParse(_chapterCtrl.text.trim()),
      evidence: evidence.isEmpty ? null : evidence,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建设定主题', style: AppTextStyles.titleLg),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._buildTitleFields(),
            const SizedBox(height: AppSpacing.sm),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('结构化这条设定（可选）', style: AppTextStyles.caption),
              children: [
                _AssertionFormFields(
                  attrCtrl: _attrCtrl,
                  valueCtrl: _valueCtrl,
                  chapterCtrl: _chapterCtrl,
                  evidenceCtrl: _evidenceCtrl,
                  errorText: _assertionError,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  /// R-019 真分解：主题名 + 设定正文（正文优先：正文是主输入，断言收折叠区）。
  List<Widget> _buildTitleFields() {
    return [
      TextField(
        controller: _nameCtrl,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '主题名（必填）',
          hintText: '如：灵气体系',
          errorText: _nameError,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _descCtrl,
        minLines: 4,
        maxLines: 8,
        decoration: const InputDecoration(
          labelText: '设定正文（推荐）',
          hintText: '先写下这个设定的内容——它是什么、怎么运作、有什么规则……',
          alignLabelWithHint: true,
        ),
      ),
    ];
  }
}

/// 追加断言弹层（真分解：StatefulWidget 独立类）。
class _AppendAssertionDialog extends StatefulWidget {
  final String themeName;

  const _AppendAssertionDialog({required this.themeName});

  @override
  State<_AppendAssertionDialog> createState() => _AppendAssertionDialogState();
}

class _AppendAssertionDialogState extends State<_AppendAssertionDialog> {
  final TextEditingController _attrCtrl = TextEditingController();
  final TextEditingController _valueCtrl = TextEditingController();
  final TextEditingController _chapterCtrl = TextEditingController();
  final TextEditingController _evidenceCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _attrCtrl.dispose();
    _valueCtrl.dispose();
    _chapterCtrl.dispose();
    _evidenceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final attr = _attrCtrl.text.trim();
    final value = _valueCtrl.text.trim();
    setState(
      () => _error = (attr.isEmpty || value.isEmpty) ? '属性和取值不能为空' : null,
    );
    if (_error != null) return;
    final evidence = _evidenceCtrl.text.trim();
    Navigator.pop(context, (
      attribute: attr,
      value: value,
      chapter: int.tryParse(_chapterCtrl.text.trim()),
      evidence: evidence.isEmpty ? null : evidence,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('追加设定 · ${widget.themeName}', style: AppTextStyles.titleLg),
      content: SingleChildScrollView(
        child: _AssertionFormFields(
          attrCtrl: _attrCtrl,
          valueCtrl: _valueCtrl,
          chapterCtrl: _chapterCtrl,
          evidenceCtrl: _evidenceCtrl,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 断言四字段（属性 / 取值 / 章节 / 原文依据）+ 常驻依据说明。
/// R-019 真分解：独立小组件，新建与追加共用（禁止复制两份）。
class _AssertionFormFields extends StatelessWidget {
  final TextEditingController attrCtrl;
  final TextEditingController valueCtrl;
  final TextEditingController chapterCtrl;
  final TextEditingController evidenceCtrl;
  final String? errorText;

  const _AssertionFormFields({
    required this.attrCtrl,
    required this.valueCtrl,
    required this.chapterCtrl,
    required this.evidenceCtrl,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: attrCtrl,
          decoration: InputDecoration(
            labelText: '属性',
            hintText: '如：灵气浓度',
            errorText: errorText,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: valueCtrl,
          decoration: const InputDecoration(labelText: '取值', hintText: '如：稀薄'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: chapterCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '章节（选填）',
            hintText: '如：3',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: evidenceCtrl,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '原文依据（选填）',
            hintText: '粘贴该设定的正文原句',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(kWorldEvidenceHint, style: AppTextStyles.caption),
      ],
    );
  }
}
