// ─────────────────────────────────────────────────────────────
// coach_selector_card — 教练人格（全局，设置页）
//
// D1/D2 Phase 2：选人卡动态化 —— 列表 = 系统预设（doubao/月笙如歌/sensei，
// 来自 CoachPersona 内置 seed）+ 用户自定义预设（来自 app_state KV
// coach_personas_custom）。选择写入 coach_persona_active KV（系统预设双写
// coach_attitude 兼容旧行为），下次启动自动沿用。
// 系统预设态度色沿用 App 既有语义：doubao=l1Text / yuesheng=l2Text / sensei=l3Text；
// 用户预设统一 primary。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../providers/app_providers.dart';
import '../../types/coach_persona.dart';
import '../../types/coach_persona_seed.dart';
import '../../types/teaching_types.dart';

class CoachSelectorCard extends ConsumerStatefulWidget {
  const CoachSelectorCard({super.key});

  @override
  ConsumerState<CoachSelectorCard> createState() => _CoachSelectorCardState();
}

class _CoachSelectorCardState extends ConsumerState<CoachSelectorCard> {
  String? _activeId;
  List<CoachPersona> _customs = const [];
  TeachingMode _mode = TeachingMode.socratic;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      final activeId = await repo.getActiveCoachPersonaId();
      final customs = await repo.getCustomCoachPersonas();
      final modeRaw = await repo.getCoachTeachingMode();
      final mode = TeachingMode.fromString(modeRaw) ?? TeachingMode.socratic;
      if (!mounted) return;
      setState(() {
        _activeId = activeId ?? 'doubao';
        _customs = customs;
        _mode = mode;
        _loading = false;
      });
    } catch (_) {
      // 读不到（测试/异常）→ 不渲染卡片，不阻塞设置页
    }
  }

  /// 展示列表：系统预设在前，用户预设在后。
  List<CoachPersona> get _all => [...builtInCoachPersonas, ..._customs];

  Future<void> _select(String personaId) async {
    try {
      await AppStateRepository(
        ref.read(appDatabaseProvider),
      ).setActiveCoachPersona(personaId);
      if (mounted) setState(() => _activeId = personaId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('教练切换失败，请稍后再试')));
      }
    }
  }

  Future<void> _selectMode(TeachingMode mode) async {
    try {
      await AppStateRepository(
        ref.read(appDatabaseProvider),
      ).setCoachTeachingMode(mode.value);
      if (mounted) setState(() => _mode = mode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('教学方式切换失败，请稍后再试')));
      }
    }
  }

  /// 打开新建/编辑自定义教练对话框；保存后刷新列表。
  Future<void> _openPersonaEditor([CoachPersona? existing]) async {
    final result = await showDialog<CoachPersona>(
      context: context,
      builder: (_) => _CustomPersonaDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      await repo.saveCustomCoachPersona(result);
      final customs = await repo.getCustomCoachPersonas();
      if (!mounted) return;
      setState(() => _customs = customs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后再试')));
      }
    }
  }

  Future<void> _deletePersona(CoachPersona persona) async {
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      await repo.removeCustomCoachPersona(persona.id);
      // 删除的正是当前激活项 → 回退系统预设 doubao。
      if (_activeId == persona.id) {
        await repo.setActiveCoachPersona('doubao');
      }
      final customs = await repo.getCustomCoachPersonas();
      if (!mounted) return;
      setState(() {
        _customs = customs;
        if (_activeId == persona.id) _activeId = 'doubao';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后再试')));
      }
    }
  }

  /// 打开系统预设的直接说明阈值编辑对话框（Part A 补：系统预设可编辑阈值）。
  Future<void> _openThresholdEditor(CoachPersona persona) async {
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    final current = await repo.getCoachPersonaDirectThreshold(persona.id) ??
        persona.directExplainThreshold;
    if (!mounted) return;
    final controller = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${persona.name} · 症候直接说明阈值'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '症候数超过该值时，当轮直接逐条说明全部症候',
            helperText: '默认 5，填 1 及以上',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 1) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await repo.setCoachPersonaDirectThreshold(persona.id, result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请稍后再试')),
        );
      }
    }
  }

  Color _personaColor(AppPalette p, CoachPersona persona) {
    if (persona.isSystem) {
      return switch (persona.attitudeLevel) {
        AttitudeLevel.doubao => p.l1Text,
        AttitudeLevel.yuesheng => p.l2Text,
        AttitudeLevel.sensei => p.l3Text,
      };
    }
    return p.primary;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(palette),
          const SizedBox(height: 4),
          Text(
            '换一种说话方式。切换后下次启动沿用。',
            style: TextStyle(fontSize: 13, color: palette.textTertiary),
          ),
          const SizedBox(height: 12),
          for (final persona in _all)
            _personaRow(
              context,
              persona: persona,
              selected: persona.id == _activeId,
              onTap: () => _select(persona.id),
              onDelete: persona.isSystem
                  ? null
                  : () => _deletePersona(persona),
              onEditThreshold: persona.isSystem
                  ? () => _openThresholdEditor(persona)
                  : null,
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => _openPersonaEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('自定义教练'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          ),
          const SizedBox(height: 12),
          _modeHeaderRow(palette),
          const SizedBox(height: 4),
          Text(
            '决定教练用提问引导，还是直接给答案。与上方人格正交。',
            style: TextStyle(fontSize: 13, color: palette.textTertiary),
          ),
          const SizedBox(height: 10),
          _modeToggle(palette),
        ],
      ),
    );
  }

  Widget _headerRow(AppPalette palette) => Row(
    children: [
      Icon(Icons.psychology_outlined, size: 18, color: palette.primary),
      const SizedBox(width: 6),
      Text(
        '教练人格',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '全局',
          style: TextStyle(fontSize: 11, color: palette.primary),
        ),
      ),
    ],
  );

  Widget _personaRow(
    BuildContext context, {
    required CoachPersona persona,
    required bool selected,
    required VoidCallback onTap,
    required VoidCallback? onDelete,
    VoidCallback? onEditThreshold,
  }) {
    final palette = context.palette;
    final color = _personaColor(palette, persona);
    final isCustom = !persona.isSystem;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? palette.primary : palette.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            _coachNameDesc(
              palette,
              persona.name,
              '${isCustom ? '自定义 · ' : ''}${persona.label}',
            ),
            if (selected)
              Icon(Icons.check_circle, size: 18, color: palette.primary),
            if (isCustom && onDelete != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: palette.textTertiary,
                ),
              ),
            ],
            if (onEditThreshold != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onEditThreshold,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Icon(
                  Icons.tune,
                  size: 18,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _coachNameDesc(AppPalette palette, String name, String desc) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ],
        ),
      );

  Widget _modeHeaderRow(AppPalette palette) => Row(
    children: [
      Icon(Icons.help_outline, size: 18, color: palette.primary),
      const SizedBox(width: 6),
      Text(
        '教学方式',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '全局',
          style: TextStyle(fontSize: 11, color: palette.primary),
        ),
      ),
    ],
  );

  Widget _modeToggle(AppPalette palette) => Row(
    children: [
      _modeChip(
        context,
        mode: TeachingMode.socratic,
        name: '疑问式',
        desc: '用提问引导你自己发现，不直接给答案',
        selected: _mode == TeachingMode.socratic,
        onTap: () => _selectMode(TeachingMode.socratic),
      ),
      const SizedBox(width: 8),
      _modeChip(
        context,
        mode: TeachingMode.direct,
        name: '直接说',
        desc: '直接指出问题与改法，不绕弯',
        selected: _mode == TeachingMode.direct,
        onTap: () => _selectMode(TeachingMode.direct),
      ),
    ],
  );

  Widget _modeChip(
    BuildContext context, {
    required TeachingMode mode,
    required String name,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: _modeChipDecoration(palette, selected),
          child: _modeChipBody(palette, name, desc, selected),
        ),
      ),
    );
  }

  BoxDecoration _modeChipDecoration(AppPalette palette, bool selected) =>
      BoxDecoration(
        color: selected ? palette.primarySoft : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: selected ? palette.primary : palette.border),
      );

  Widget _modeChipBody(
    AppPalette palette,
    String name,
    String desc,
    bool selected,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const Spacer(),
          if (selected)
            Icon(Icons.check_circle, size: 18, color: palette.primary),
        ],
      ),
      const SizedBox(height: 2),
      Text(desc, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
    ],
  );
}

/// 新建/编辑自定义教练对话框。
class _CustomPersonaDialog extends StatefulWidget {
  final CoachPersona? existing;

  const _CustomPersonaDialog({this.existing});

  @override
  State<_CustomPersonaDialog> createState() => _CustomPersonaDialogState();
}

class _CustomPersonaDialogState extends State<_CustomPersonaDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _promptCtrl;
  late final TextEditingController _layerCtrl;
  late final TextEditingController _thresholdCtrl;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    _promptCtrl = TextEditingController(text: e?.systemPromptFragment ?? '');
    _layerCtrl = TextEditingController(text: e?.personaLayer ?? '');
    _thresholdCtrl =
        TextEditingController(text: (e?.directExplainThreshold ?? 5).toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _labelCtrl.dispose();
    _promptCtrl.dispose();
    _layerCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final label = _labelCtrl.text.trim();
    final prompt = _promptCtrl.text.trim();
    final layer = _layerCtrl.text.trim();
    final threshold = int.tryParse(_thresholdCtrl.text.trim()) ?? 5;
    if (name.isEmpty || prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称和语气设定不能为空')),
      );
      return;
    }
    final e = widget.existing;
    final persona = CoachPersona(
      id: e?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      label: label.isEmpty ? '自定义教练' : label,
      isSystem: false,
      attitudeLevel: AttitudeLevel.doubao,
      systemPromptFragment: prompt,
      personaLayer: layer.isEmpty ? null : layer,
      iconKey: e?.iconKey,
      directExplainThreshold: threshold < 1 ? 5 : threshold,
    );
    Navigator.of(context).pop(persona);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(_isEdit ? '编辑自定义教练' : '新建自定义教练'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：毒舌编辑',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: '一句话声音描述（选填）',
                hintText: '如：犀利、直给、不许废话',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _promptCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '语气/角色设定',
                hintText: '教它怎么说话，会注入到系统提示里',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _layerCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '人设层 / 角色口吻（选填，D2）',
                hintText: '叠加在语气之上，如：以资深文学编辑口吻，多用比喻',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '症候直接说明阈值（数字）',
                helperText: '诊断出超过该数量的症候时，当轮直接逐条说明全部症候',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: palette.textSecondary)),
        ),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
